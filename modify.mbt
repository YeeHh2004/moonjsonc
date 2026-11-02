///|
fn modify_document(text : String) -> Result[Document, EditError] {
  let document = parse(text, options={
    ..ParseOptions::default(),
    allow_empty: true,
  })
  if document.diagnostics.is_empty() {
    Ok(document)
  } else {
    Err(InvalidDocument(document.diagnostics))
  }
}

///|
fn modify_options(options : FormatOptions) -> Result[Unit, EditError] {
  if options.indent_size < 0 ||
    options.indent_size > 16 ||
    (options.eol != "\n" && options.eol != "\r\n" && options.eol != "\r") {
    Err(
      InvalidOptions("indent size must be 0..16 and EOL must be LF, CRLF or CR"),
    )
  } else {
    Ok(())
  }
}

///|
fn modify_value(
  value : String,
  options : FormatOptions,
) -> Result[String, EditError] {
  let document = parse(value, options={
    ..ParseOptions::default(),
    allow_comments: false,
    allow_trailing_comma: false,
  })
  if !document.diagnostics.is_empty() {
    return Err(InvalidValue(document.diagnostics))
  }
  let node = match document.root {
    Some(node) => node
    None => return Err(InvalidValue([]))
  }
  let source = edit_slice(value, node.offset, node.offset + node.length)
  match format(source, options={ ..options, final_newline: false, }) {
    Err(error) => Err(error)
    Ok(edits) => apply_edits(source, edits)
  }
}

///|
fn modify_key(node : Node) -> String {
  match node.children[0].value {
    String(key) => key
    _ => ""
  }
}

///|
fn modify_indent(text : String, position : Int) -> String {
  let mut start = position
  while start > 0 &&
        text.unsafe_get(start - 1) != 10 &&
        text.unsafe_get(start - 1) != 13 {
    start -= 1
  }
  let mut end = start
  while end < position &&
        (text.unsafe_get(end) == 32 || text.unsafe_get(end) == 9) {
    end += 1
  }
  edit_slice(text, start, end)
}

///|
fn modify_unit(options : FormatOptions) -> String {
  if options.use_tabs {
    "\t"
  } else {
    String::make(options.indent_size, ' ')
  }
}

///|
fn modify_reindent(text : String, indent : String) -> String {
  let out = StringBuilder()
  let mut previous_cr = false
  for c in text {
    if previous_cr && c != '\n' {
      out.write_string(indent)
    }
    out.write_string(c.to_string())
    if c == '\n' {
      out.write_string(indent)
    }
    previous_cr = c == '\r'
  }
  if previous_cr {
    out.write_string(indent)
  }
  out.to_string()
}

///|
fn modify_comma(tokens : Array[Token], start : Int, end : Int) -> Token? {
  for token in tokens {
    if token.offset >= end {
      break
    }
    if token.offset >= start && token.kind == Comma {
      return Some(token)
    }
  }
  None
}

///|
fn modify_finish(
  text : String,
  edits : Array[TextEdit],
) -> Result[Array[TextEdit], EditError] {
  match apply_edits(text, edits) {
    Err(error) => Err(error)
    Ok(next) =>
      match modify_document(next) {
        Err(_) =>
          Err(InvalidEdit("the requested change would produce invalid JSONC"))
        Ok(_) => Ok(edits)
      }
  }
}

///|
fn modify_append(
  text : String,
  document : Document,
  parent : Node,
  entry : String,
  options : FormatOptions,
) -> Result[Array[TextEdit], EditError] {
  let close = parent.offset + parent.length - 1
  let multiline = edit_slice(text, parent.offset, close).contains_char('\n') ||
    edit_slice(text, parent.offset, close).contains_char('\r')
  let count = parent.children.length()
  let last_end = if count == 0 {
    parent.offset + 1
  } else {
    let last = parent.children[count - 1]
    last.offset + last.length
  }
  let trailing = modify_comma(document.tokens, last_end, close)
  let edits : Array[TextEdit] = []
  let mut position = close
  let mut content = ""
  if multiline {
    let parent_indent = modify_indent(text, parent.offset)
    let close_indent = modify_indent(text, close)
    let before_close = close - close_indent.length()
    let close_on_own_line = before_close == 0 ||
      edit_slice(text, before_close - 1, before_close) == "\n" ||
      edit_slice(text, before_close - 1, before_close) == "\r"
    let child_indent = if count > 0 {
      let first = parent.children[0]
      let existing = modify_indent(text, first.offset)
      if existing.length() > parent_indent.length() {
        existing
      } else {
        parent_indent + modify_unit(options)
      }
    } else {
      parent_indent + modify_unit(options)
    }
    if close_on_own_line {
      position = before_close
    }
    let prefix = if close_on_own_line { "" } else { options.eol }
    content = prefix +
      child_indent +
      modify_reindent(entry, child_indent) +
      (if trailing is Some(_) { "," } else { "" }) +
      options.eol +
      (if close_on_own_line { "" } else { parent_indent })
  } else {
    content = (if count == 0 { "" } else { " " }) +
      entry +
      (if trailing is Some(_) { "," } else { "" })
  }
  if count > 0 && trailing is None {
    if last_end == position {
      content = "," + content
    } else {
      edits.push({ offset: last_end, length: 0, content: ",", })
    }
  }
  edits.push({ offset: position, length: 0, content, })
  modify_finish(text, edits)
}

///|
fn modify_remove_item(
  text : String,
  document : Document,
  parent : Node,
  index : Int,
) -> Result[Array[TextEdit], EditError] {
  let item = parent.children[index]
  let edits : Array[TextEdit] = [
    { offset: item.offset, length: item.length, content: "", },
  ]
  let close = parent.offset + parent.length - 1
  let comma = if index + 1 < parent.children.length() {
    modify_comma(
      document.tokens,
      item.offset + item.length,
      parent.children[index + 1].offset,
    )
  } else if index > 0 {
    let previous = parent.children[index - 1]
    modify_comma(
      document.tokens,
      previous.offset + previous.length,
      item.offset,
    )
  } else {
    modify_comma(document.tokens, item.offset + item.length, close)
  }
  if comma is Some(token) {
    edits.push({ offset: token.offset, length: token.length, content: "", })
  }
  modify_finish(text, edits)
}

///|
fn modify_nested(
  path : Array[PathSegment],
  from : Int,
  value : String,
) -> Result[String, EditError] {
  if from == path.length() {
    return Ok(value)
  }
  let child = match modify_nested(path, from + 1, value) {
    Ok(child) => child
    Err(error) => return Err(error)
  }
  match path[from] {
    Key(key) => Ok("{" + key.to_json().stringify() + ": " + child + "}")
    Index(index) =>
      if index == 0 || index == -1 {
        Ok("[" + child + "]")
      } else {
        Err(
          InvalidPath(
            "new arrays start at index 0; sparse creation is not supported",
          ),
        )
      }
  }
}

///|
fn modify_empty(
  text : String,
  document : Document,
  value : String,
  options : FormatOptions,
) -> Result[Array[TextEdit], EditError] {
  let mut newline = false
  for token in document.tokens {
    if token.kind == LineComment {
      newline = true
    } else if token.kind == LineBreak {
      newline = false
    }
  }
  let content = (if newline { options.eol } else { "" }) + value
  modify_finish(text, [{ offset: text.length(), length: 0, content, }])
}

///|
fn modify_walk(
  text : String,
  document : Document,
  current : Node,
  path : Array[PathSegment],
  depth : Int,
  value : String?,
  options : FormatOptions,
) -> Result[Array[TextEdit], EditError] {
  if depth == path.length() {
    let replacement = value.unwrap_or("")
    if edit_slice(text, current.offset, current.offset + current.length) ==
      replacement {
      return Ok([])
    }
    return modify_finish(text, [
      { offset: current.offset, length: current.length, content: replacement, },
    ])
  }
  let last = depth + 1 == path.length()
  match (current.kind, path[depth]) {
    (ObjectNode, Key(key)) => {
      let mut index = -1
      for i, property in current.children {
        if modify_key(property) == key {
          index = i
          break
        }
      }
      if index >= 0 {
        if last && value is None {
          return modify_remove_item(text, document, current, index)
        }
        modify_walk(
          text,
          document,
          current.children[index].children[1],
          path,
          depth + 1,
          value,
          options,
        )
      } else {
        let supplied = match value {
          None => return Ok([])
          Some(v) => v
        }
        let nested = match modify_nested(path, depth + 1, supplied) {
          Ok(v) => v
          Err(e) => return Err(e)
        }
        let nested = match modify_value(nested, options) {
          Ok(v) => v
          Err(e) => return Err(e)
        }
        modify_append(
          text,
          document,
          current,
          key.to_json().stringify() + ": " + nested,
          options,
        )
      }
    }
    (ArrayNode, Index(requested)) => {
      let count = current.children.length()
      let index = if requested == -1 { count } else { requested }
      if index < 0 || index > count {
        return Err(InvalidPath("array index is outside 0..length"))
      }
      if index < count {
        if last && value is None {
          return modify_remove_item(text, document, current, index)
        }
        modify_walk(
          text,
          document,
          current.children[index],
          path,
          depth + 1,
          value,
          options,
        )
      } else {
        let supplied = match value {
          None => return Ok([])
          Some(v) => v
        }
        let nested = match modify_nested(path, depth + 1, supplied) {
          Ok(v) => v
          Err(e) => return Err(e)
        }
        let nested = match modify_value(nested, options) {
          Ok(v) => v
          Err(e) => return Err(e)
        }
        modify_append(text, document, current, nested, options)
      }
    }
    _ =>
      Err(
        InvalidPath(
          "path segment does not match the existing object, array or scalar",
        ),
      )
  }
}

///|
/// Set or remove a JSONC path using source-coordinate edits. None removes;
/// missing removals are idempotent. Missing parents are created without replacing
/// existing scalar data. Index -1 and length append; sparse arrays are rejected.
pub fn modify(
  text : String,
  path : Array[PathSegment],
  value : String?,
  options? : FormatOptions = FormatOptions::default(),
) -> Result[Array[TextEdit], EditError] {
  if path.length() > 128 {
    return Err(InvalidPath("path depth exceeds 128"))
  }
  match modify_options(options) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  let document = match modify_document(text) {
    Ok(d) => d
    Err(e) => return Err(e)
  }
  let prepared = match value {
    None => None
    Some(v) =>
      match modify_value(v, options) {
        Ok(v) => Some(v)
        Err(e) => return Err(e)
      }
  }
  match document.root {
    Some(root) => modify_walk(text, document, root, path, 0, prepared, options)
    None => {
      let supplied = match prepared {
        None => return Ok([])
        Some(v) => v
      }
      let nested = match modify_nested(path, 0, supplied) {
        Ok(v) => v
        Err(e) => return Err(e)
      }
      let nested = match modify_value(nested, options) {
        Ok(v) => v
        Err(e) => return Err(e)
      }
      modify_empty(text, document, nested, options)
    }
  }
}

///|
/// Insert before an existing array element, or append at length. Unlike modify,
/// this shifts existing elements. The array must exist; indices are 0..length.
pub fn insert(
  text : String,
  path : Array[PathSegment],
  index : Int,
  value : String,
  options? : FormatOptions = FormatOptions::default(),
) -> Result[Array[TextEdit], EditError] {
  if path.length() > 128 {
    return Err(InvalidPath("path depth exceeds 128"))
  }
  match modify_options(options) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  let document = match modify_document(text) {
    Ok(d) => d
    Err(e) => return Err(e)
  }
  let root = match document.root {
    Some(n) => n
    None => return Err(InvalidPath("array does not exist"))
  }
  let parent = match find_node(root, path) {
    Some(n) => n
    None => return Err(InvalidPath("array does not exist"))
  }
  if parent.kind != ArrayNode {
    return Err(InvalidPath("insert requires an array"))
  }
  let count = parent.children.length()
  if index < 0 || index > count {
    return Err(InvalidPath("insertion index is outside 0..length"))
  }
  let supplied = match modify_value(value, options) {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  if index == count {
    return modify_append(text, document, parent, supplied, options)
  }
  let position = if index == 0 {
    parent.offset + 1
  } else {
    let previous = parent.children[index - 1]
    match
      modify_comma(
        document.tokens,
        previous.offset + previous.length,
        parent.children[index].offset,
      ) {
      Some(comma) => comma.offset + comma.length
      None => return Err(InvalidEdit("array separator is missing"))
    }
  }
  let multiline = edit_slice(text, parent.offset, parent.offset + parent.length).contains_char(
      '\n',
    ) ||
    edit_slice(text, parent.offset, parent.offset + parent.length).contains_char(
      '\r',
    )
  let prefix = if multiline {
    options.eol + modify_indent(text, parent.children[index].offset)
  } else if index > 0 {
    " "
  } else {
    ""
  }
  let content = prefix +
    modify_reindent(
      supplied,
      if multiline {
        modify_indent(text, parent.children[index].offset)
      } else {
        ""
      },
    ) +
    ","
  modify_finish(text, [{ offset: position, length: 0, content, }])
}
