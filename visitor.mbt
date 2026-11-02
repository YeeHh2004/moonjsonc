///|
/// Source-ordered visitor events. value preserves numeric spelling and comment text.
pub(all) struct Event {
  kind : String
  offset : Int
  length : Int
  path : Array[PathSegment]
  value : String
} derive(Eq, @debug.Debug)

///|
priv struct VisitFrame {
  path : Array[PathSegment]
  object : Bool
  mut key : String
  mut index : Int
  mut expecting_key : Bool
}

///| Visit a previously parsed document. Return false to stop; returns delivered count.

///|
/// Trivia whitespace is omitted; comments and separators are delivered explicitly.
pub fn visit(doc : Document, callback : (Event) -> Bool) -> Int {
  let mut delivered = 0
  let stack : Array[VisitFrame] = []
  for token in doc.tokens {
    let mut path : Array[PathSegment] = []
    let mut property = false
    if !stack.is_empty() {
      let parent = stack[stack.length() - 1]
      if parent.object {
        if parent.expecting_key && token.kind == StringToken {
          parent.key = token.value
          property = true
        }
        path = path_with(parent.path, Key(parent.key))
      } else {
        path = path_with(parent.path, Index(parent.index))
      }
    }
    let kind = match token.kind {
      OpenBrace | OpenBracket => {
        stack.push({
          path,
          object: token.kind == OpenBrace,
          key: "",
          index: 0,
          expecting_key: token.kind == OpenBrace,
        })
        if token.kind == OpenBrace {
          "object_begin"
        } else {
          "array_begin"
        }
      }
      CloseBrace | CloseBracket => {
        match stack.pop() {
          Some(frame) => path = frame.path
          None => ()
        }
        if token.kind == CloseBrace {
          "object_end"
        } else {
          "array_end"
        }
      }
      StringToken => if property { "property" } else { "literal" }
      NumberToken | TrueToken | FalseToken | NullToken => "literal"
      Colon | Comma => {
        if !stack.is_empty() {
          let parent = stack[stack.length() - 1]
          if token.kind == Colon {
            parent.expecting_key = false
          } else if parent.object {
            parent.expecting_key = true
            parent.key = ""
          } else {
            parent.index += 1
          }
        }
        "separator"
      }
      LineComment | BlockComment => "comment"
      Unknown => "unknown"
      _ => continue
    }
    delivered += 1
    if !callback({
        kind,
        offset: token.offset,
        length: token.length,
        path,
        value: token.value,
      }) {
      break
    }
  }
  delivered
}

///|
pub extend Event with Eq::{equal, not_equal}

///|
pub extend Event with @debug.Debug::{to_repr}
