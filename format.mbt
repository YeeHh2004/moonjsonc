///|
fn format_boundary(text : String, offset : Int) -> Bool {
  if offset < 0 || offset > text.length() {
    return false
  }
  if offset == 0 || offset == text.length() {
    return true
  }
  let previous = text.unsafe_get(offset - 1)
  let next = text.unsafe_get(offset)
  !(previous >= 0xD800 && previous <= 0xDBFF && next >= 0xDC00 && next <= 0xDFFF)
}

///|
fn format_line_break(code : UInt16) -> Bool {
  code == 10 || code == 13
}

///|
/// A range selects complete original source lines. CRLF is one line break.
fn format_line_range(text : String, range : TextRange) -> TextRange {
  let mut start = range.offset
  if start > 0 &&
    start < text.length() &&
    text.unsafe_get(start - 1) == 13 &&
    text.unsafe_get(start) == 10 {
    start -= 1
  }
  while start > 0 && !format_line_break(text.unsafe_get(start - 1)) {
    start -= 1
  }
  let mut end = if range.length > 0 {
    range.offset + range.length - 1
  } else {
    range.offset
  }
  while end < text.length() && !format_line_break(text.unsafe_get(end)) {
    end += 1
  }
  if end < text.length() {
    if text.unsafe_get(end) == 13 &&
      end + 1 < text.length() &&
      text.unsafe_get(end + 1) == 10 {
      end += 2
    } else {
      end += 1
    }
  }
  { offset: start, length: end - start, }
}

///|
fn format_indent(depth : Int, options : FormatOptions) -> String {
  if options.use_tabs {
    String::make(depth, '\t')
  } else {
    String::make(depth * options.indent_size, ' ')
  }
}

///|
fn format_has_break(text : StringView) -> Bool {
  for c in text {
    if c == '\r' || c == '\n' {
      return true
    }
  }
  false
}

///|
fn format_comment(kind : TokenKind) -> Bool {
  kind == LineComment || kind == BlockComment
}

///|
/// Plan only whitespace changes, trimming unchanged prefixes and suffixes.
fn format_gap(
  text : String,
  start : Int,
  end : Int,
  content : String,
  range : TextRange,
  edits : Array[TextEdit],
) -> Unit {
  let old = text.view(start_offset=start, end_offset=end)
  let mut prefix = 0
  while prefix < old.length() &&
        prefix < content.length() &&
        old.unsafe_get(prefix) == content.unsafe_get(prefix) {
    prefix += 1
  }
  let mut suffix = 0
  while suffix < old.length() - prefix &&
        suffix < content.length() - prefix &&
        old.unsafe_get(old.length() - 1 - suffix) ==
        content.unsafe_get(content.length() - 1 - suffix) {
    suffix += 1
  }
  let offset = start + prefix
  let length = old.length() - prefix - suffix
  let replacement = content
    .view(start_offset=prefix, end_offset=content.length() - suffix)
    .to_owned()
  if length == 0 && replacement == "" {
    return
  }
  let range_end = range.offset + range.length
  // A zero-length insertion at the next line's start belongs to that next line.
  if offset >= range.offset &&
    offset + length <= range_end &&
    (offset < range_end || range_end == text.length()) {
    edits.push({ offset, length, content: replacement, })
  }
}

///| Format valid JSONC using edits that change only whitespace between tokens.

///| String, number and comment token spelling is preserved exactly. Options

///| accept indentation 0..16 and LF/CRLF/CR. Empty documents are rejected.

///| A range uses original UTF-16 coordinates and expands to complete source

///| lines. Only minimized edits wholly within those lines are returned; a gap

///| requiring a change across their boundary is left untouched. Formatting

///|
/// context is nevertheless computed from the complete document.
pub fn format(
  text : String,
  options? : FormatOptions = FormatOptions::default(),
  range? : TextRange? = None,
) -> Result[Array[TextEdit], EditError] {
  if options.indent_size < 0 || options.indent_size > 16 {
    return Err(InvalidOptions("indent_size must be between 0 and 16"))
  }
  if options.eol != "\n" && options.eol != "\r\n" && options.eol != "\r" {
    return Err(InvalidOptions("eol must be LF, CRLF or CR"))
  }
  let selected = match range {
    None => { offset: 0, length: text.length(), }
    Some(range) => {
      if range.offset < 0 ||
        range.length < 0 ||
        range.offset > text.length() ||
        range.length > text.length() - range.offset ||
        !format_boundary(text, range.offset) ||
        !format_boundary(text, range.offset + range.length) {
        return Err(
          InvalidOptions("range must use valid UTF-16 source boundaries"),
        )
      }
      format_line_range(text, range)
    }
  }
  let document = parse(text)
  if !document.diagnostics.is_empty() {
    return Err(InvalidDocument(document.diagnostics))
  }
  let tokens = document.tokens.filter(fn(token) {
    token.kind != Whitespace && token.kind != LineBreak && token.kind != Eof
  })
  let edits : Array[TextEdit] = []
  let mut depth = 0
  let mut previous : Token? = None
  let mut end = 0
  for token in tokens {
    if token.kind == CloseBrace || token.kind == CloseBracket {
      depth -= 1
    }
    let newline = options.eol + format_indent(depth, options)
    let original = text.view(start_offset=end, end_offset=token.offset)
    let gap = match previous {
      None => ""
      Some(previous) => {
        let empty = (previous.kind == OpenBrace && token.kind == CloseBrace) ||
          (previous.kind == OpenBracket && token.kind == CloseBracket)
        if empty {
          ""
        } else if previous.kind == LineComment {
          newline
        } else if token.kind == CloseBrace || token.kind == CloseBracket {
          newline
        } else if previous.kind == OpenBrace || previous.kind == OpenBracket {
          newline
        } else if format_comment(token.kind) {
          if format_has_break(original) {
            newline
          } else {
            " "
          }
        } else if previous.kind == Comma {
          newline
        } else if previous.kind == Colon {
          " "
        } else if previous.kind == BlockComment {
          let body = text.view(
            start_offset=previous.offset,
            end_offset=previous.offset + previous.length,
          )
          if format_has_break(original) || format_has_break(body) {
            newline
          } else if token.kind == Colon || token.kind == Comma {
            ""
          } else {
            " "
          }
        } else if token.kind == Colon || token.kind == Comma {
          ""
        } else if format_has_break(original) {
          newline
        } else {
          " "
        }
      }
    }
    format_gap(text, end, token.offset, gap, selected, edits)
    if token.kind == OpenBrace || token.kind == OpenBracket {
      depth += 1
    }
    end = token.offset + token.length
    previous = Some(token)
  }
  format_gap(
    text,
    end,
    text.length(),
    if options.final_newline {
      options.eol
    } else {
      ""
    },
    selected,
    edits,
  )
  Ok(edits)
}
