///|
fn transaction_members(node : Node) -> Array[(String, Node)] {
  let result : Array[(String, Node)] = []
  for property in node.children {
    result.push((modify_key(property), property.children[1]))
  }
  result.sort_by(fn(a, b) {
    if a.0 < b.0 {
      -1
    } else if a.0 > b.0 {
      1
    } else {
      0
    }
  })
  result
}

///|
fn transaction_equal(
  left : Node,
  left_text : String,
  right : Node,
  right_text : String,
) -> Bool {
  if left.kind != right.kind {
    return false
  }
  match left.kind {
    NumberNode =>
      edit_slice(left_text, left.offset, left.offset + left.length) ==
      edit_slice(right_text, right.offset, right.offset + right.length)
    ObjectNode => {
      if left.children.length() != right.children.length() {
        return false
      }
      let a = transaction_members(left)
      let b = transaction_members(right)
      for i, (key, value) in a {
        if key != b[i].0 ||
          !transaction_equal(value, left_text, b[i].1, right_text) {
          return false
        }
      }
      true
    }
    ArrayNode => {
      if left.children.length() != right.children.length() {
        return false
      }
      for i, child in left.children {
        if !transaction_equal(child, left_text, right.children[i], right_text) {
          return false
        }
      }
      true
    }
    _ => left.value == right.value
  }
}

///|
fn transaction_diff(before : String, after : String) -> Array[TextEdit] {
  if before == after {
    return []
  }
  let a = before.to_array()
  let b = after.to_array()
  let mut prefix = 0
  while prefix < a.length() && prefix < b.length() && a[prefix] == b[prefix] {
    prefix += 1
  }
  let mut suffix = 0
  while suffix < a.length() - prefix &&
        suffix < b.length() - prefix &&
        a[a.length() - suffix - 1] == b[b.length() - suffix - 1] {
    suffix += 1
  }
  let mut offset = 0
  for i in 0..<prefix {
    offset += a[i].utf16_len()
  }
  let mut removed = 0
  for i in prefix..<(a.length() - suffix) {
    removed += a[i].utf16_len()
  }
  let inserted : Array[Char] = []
  for i in prefix..<(b.length() - suffix) {
    inserted.push(b[i])
  }
  [{ offset, length: removed, content: String::from_array(inserted), }]
}

///|
fn transaction_preflight(
  operations : Array[Operation],
  options : FormatOptions,
) -> Result[Unit, EditError] {
  if operations.length() > 1000 {
    return Err(InvalidEdit("transaction exceeds 1000 operations"))
  }
  let mut total = 0
  for operation in operations {
    let (path, value) = match operation {
      Set(path, value) | Test(path, value) | Insert(path, _, value) =>
        (path, Some(value))
      Remove(path) => (path, None)
    }
    if path.length() > 128 {
      return Err(InvalidPath("path depth exceeds 128"))
    }
    for segment in path {
      if segment is Index(index) && index < -1 {
        return Err(
          InvalidPath("negative indices other than append -1 are invalid"),
        )
      }
    }
    if value is Some(source) {
      if source.length() > 8388608 - total {
        return Err(InvalidEdit("transaction values exceed 8 Mi UTF-16 units"))
      }
      total += source.length()
      match modify_value(source, options) {
        Err(e) => return Err(e)
        Ok(_) => ()
      }
    }
    if operation is Insert(_, index, _) && index < 0 {
      return Err(InvalidPath("insertion index cannot be negative"))
    }
  }
  Ok(())
}

///|
/// Apply a sequence in memory, committing no partial result on failure.
/// Test ignores object order and spelling of decoded strings, preserves array
/// order, and compares numbers by their exact JSON lexeme (1 differs from 1.0).
/// applied counts successful operations including Test and no-op removals.
/// The final patch uses original-source coordinates and can be applied once.
pub fn transact(
  text : String,
  operations : Array[Operation],
  options? : FormatOptions = FormatOptions::default(),
  expected_source? : String? = None,
) -> Result[Transaction, EditError] {
  if expected_source is Some(expected) && text != expected {
    return Err(Conflict("source differs from the expected snapshot"))
  }
  match modify_options(options) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  match modify_document(text) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  match transaction_preflight(operations, options) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  let mut current = text
  for operation in operations {
    let edits = match operation {
      Set(path, value) => modify(current, path, Some(value), options~)
      Remove(path) => modify(current, path, None, options~)
      Insert(path, index, value) =>
        insert(current, path, index, value, options~)
      Test(path, expected) => {
        let document = match modify_document(current) {
          Ok(d) => d
          Err(e) => return Err(e)
        }
        let root = match document.root {
          Some(n) => n
          None => return Err(Conflict("test path does not exist"))
        }
        let actual = match find_node(root, path) {
          Some(n) => n
          None => return Err(Conflict("test path does not exist"))
        }
        let expected_document = parse(expected, options={
          ..ParseOptions::default(),
          allow_comments: false,
          allow_trailing_comma: false,
        })
        let expected_node = match expected_document.root {
          Some(n) => n
          None => return Err(InvalidValue(expected_document.diagnostics))
        }
        if !transaction_equal(actual, current, expected_node, expected) {
          return Err(Conflict("test value does not match"))
        }
        Ok([])
      }
    }
    let edits = match edits {
      Ok(edits) => edits
      Err(e) => return Err(e)
    }
    current = match apply_edits(current, edits) {
      Ok(next) => next
      Err(e) => return Err(e)
    }
  }
  Ok({
    text: current,
    edits: transaction_diff(text, current),
    applied: operations.length(),
  })
}
