///| Source positions are zero-based UTF-16 line and column indices.
pub(all) struct Location {
  path : Array[PathSegment]
  is_property_key : Bool
  offset : Int
  line : Int
  column : Int
} derive(Eq, @debug.Debug)

///|
fn path_with(path : Array[PathSegment], part : PathSegment) -> Array[PathSegment] {
  let result = path.copy()
  result.push(part)
  result
}

///|
fn has_comma(doc : Document, start : Int, end : Int) -> Bool {
  for token in doc.tokens {
    if token.offset >= end { break }
    if token.offset >= start && token.kind == Comma { return true }
  }
  false
}

///|
fn locate_node(doc : Document, node : Node, at : Int, path : Array[PathSegment]) -> (Array[PathSegment], Bool) {
  if at <= node.offset || at >= node.offset + node.length - 1 {
    if node.kind == ObjectNode || node.kind == ArrayNode { return (path, false) }
  }
  match node.kind {
    ObjectNode => {
      for property in node.children {
        if property.children.is_empty() { continue }
        let key = property.children[0]
        let name = match key.value { String(s) => s; _ => "" }
        let next = path_with(path, Key(name))
        if at < key.offset { return (path_with(path, Key("")), true) }
        if at < key.offset + key.length { return (next, true) }
        if property.children.length() < 2 {
          if at <= property.offset + property.length { return (next, false) }
        } else {
          let value = property.children[1]
          if at < value.offset { return (next, false) }
          if at < value.offset + value.length { return locate_node(doc, value, at, next) }
          let end = value.offset + value.length
          if !has_comma(doc, end, at + 1) { return (next, false) }
        }
      }
      (path_with(path, Key("")), true)
    }
    ArrayNode => {
      for index, value in node.children {
        let next = path_with(path, Index(index))
        if at < value.offset { return (next, false) }
        if at < value.offset + value.length { return locate_node(doc, value, at, next) }
        if !has_comma(doc, value.offset + value.length, at + 1) { return (next, false) }
      }
      (path_with(path, Index(node.children.length())), false)
    }
    _ => (path, false)
  }
}

///| Find an editor cursor's structural path, including unfinished property slots.
///| Empty Key("") denotes an object key slot; use is_property_key to distinguish it.
pub fn get_location(doc : Document, offset : Int) -> Result[Location, EditError] {
  if offset < 0 || offset > doc.text.length() {
    return Err(InvalidEdit("cursor offset is outside the source"))
  }
  let mut line = 0
  let mut column = 0
  let mut i = 0
  while i < offset {
    let c = doc.text.code_unit_at(i)
    if c == 13 {
      line += 1
      column = 0
      if i + 1 < offset && doc.text.code_unit_at(i + 1) == 10 { i += 1 }
    } else if c == 10 {
      line += 1
      column = 0
    } else { column += 1 }
    i += 1
  }
  let (path, is_property_key) = match doc.root {
    Some(root) => locate_node(doc, root, offset, [])
    None => ([], false)
  }
  Ok({ path, is_property_key, offset, line, column })
}

///| Encode a typed path as RFC 6901 JSON Pointer. Numeric object keys stay keys.
pub fn to_pointer(path : Array[PathSegment]) -> String {
  let mut result = ""
  for part in path {
    let value = match part { Key(s) => s; Index(i) => i.to_string() }
    result += "/"
    for c in value {
      result += match c { '~' => "~0"; '/' => "~1"; _ => c.to_string() }
    }
  }
  result
}

///|
pub extend Location with Eq::{equal, not_equal}

///|
pub extend Location with @debug.Debug::{to_repr}
