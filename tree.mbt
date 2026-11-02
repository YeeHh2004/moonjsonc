///|
/// Resolve an exact path. Duplicate matching keys are intentionally ambiguous.
pub fn find_node(root : Node, path : Array[PathSegment]) -> Node? {
  let mut current = root
  for segment in path {
    match segment {
      Index(index) => {
        if current.kind != ArrayNode ||
          index < 0 ||
          index >= current.children.length() {
          return None
        }
        current = current.children[index]
      }
      Key(name) => {
        if current.kind != ObjectNode {
          return None
        }
        let mut found : Node? = None
        for property in current.children {
          if property.kind == PropertyNode && property.children.length() == 2 {
            match property.children[0].value {
              String(key) =>
                if key == name {
                  if found is Some(_) {
                    return None
                  }
                  found = Some(property.children[1])
                }
              _ => ()
            }
          }
        }
        match found {
          Some(node) => current = node
          None => return None
        }
      }
    }
  }
  Some(current)
}

///|
/// Cached JSON projection of a parsed node. Keep source spans for exact numbers;
/// a Double estimate cannot represent every valid JSON numeric spelling.
pub fn node_value(node : Node) -> Json {
  node.value
}

///|
/// Return the deepest containing node. Ranges are half-open unless explicitly
/// including the right endpoint; ties prefer the earlier source child.
pub fn node_at_offset(
  node : Node,
  offset : Int,
  include_right_bound? : Bool = false,
) -> Node? {
  fn contains(value : Node) -> Bool {
    offset >= value.offset &&
    (
      offset < value.offset + value.length ||
      (include_right_bound && offset == value.offset + value.length)
    )
  }
  if !contains(node) {
    return None
  }
  let mut current = node
  // Parsed trees are bounded; this also prevents hostile, caller-constructed
  // cyclic child arrays from trapping an inspection operation forever.
  for _ in 0..<1024 {
    let mut next : Node? = None
    for child in current.children {
      if contains(child) {
        next = Some(child)
        break
      }
    }
    match next {
      None => return Some(current)
      Some(child) => current = child
    }
  }
  Some(current)
}
