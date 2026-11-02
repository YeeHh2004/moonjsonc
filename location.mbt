///|
/// Source positions are zero-based UTF-16 line and column indices.
pub(all) struct Location {
  path : Array[PathSegment]
  is_property_key : Bool
  offset : Int
  line : Int
  column : Int
} derive(Eq, @debug.Debug)

///|
fn path_with(
  path : Array[PathSegment],
  part : PathSegment,
) -> Array[PathSegment] {
  let result = path.copy()
  result.push(part)
  result
}

///|
priv enum LocatePhase {
  LocKey
  LocColon
  LocValue
  LocDone
} derive(Eq)

///|
priv struct LocateFrame {
  object : Bool
  mut phase : LocatePhase
  mut key : String
  mut index : Int
}

///| Track the source prefix, rather than inferring cursor state from recovered

///| tree spans. A comma, colon or bracket affects the position only after its

///| source unit has passed the cursor. Property strings supply their decoded

///| name at their opening quote and remain key positions until after the colon.

///| The stack also retains useful insertion slots at an unfinished document's

///|
/// EOF, where a recovered tree's final span cannot distinguish open and closed.
fn location_prefix(doc : Document, at : Int) -> (Array[PathSegment], Bool) {
  let stack : Array[LocateFrame] = []
  let mut started = false
  for token in doc.tokens {
    if token.offset > at {
      break
    }
    match token.kind {
      OpenBrace | OpenBracket => {
        if token.offset == at {
          break
        }
        if stack.is_empty() {
          if started {
            continue
          }
        } else {
          let parent = stack[stack.length() - 1]
          if parent.object &&
            (parent.phase == LocKey || parent.phase == LocDone) {
            continue
          }
          parent.phase = LocDone
        }
        started = true
        let object = token.kind == OpenBrace
        stack.push({
          object,
          phase: if object {
            LocKey
          } else {
            LocValue
          },
          key: "",
          index: 0,
        })
      }
      CloseBrace | CloseBracket => {
        if token.offset == at {
          break
        }
        if !stack.is_empty() {
          let frame = stack[stack.length() - 1]
          if frame.object == (token.kind == CloseBrace) {
            stack.pop() |> ignore
          }
        }
      }
      Colon => {
        if token.offset == at {
          break
        }
        if !stack.is_empty() {
          let frame = stack[stack.length() - 1]
          if frame.object {
            frame.phase = LocValue
          }
        }
      }
      Comma => {
        if token.offset == at {
          break
        }
        if !stack.is_empty() {
          let frame = stack[stack.length() - 1]
          if frame.object {
            frame.key = ""
            frame.phase = LocKey
          } else {
            frame.index += 1
            frame.phase = LocValue
          }
        }
      }
      StringToken => {
        if !stack.is_empty() {
          let frame = stack[stack.length() - 1]
          if frame.object && (frame.phase == LocKey || frame.phase == LocDone) {
            frame.key = token.value
            frame.phase = LocColon
          } else {
            frame.phase = LocDone
          }
        }
        started = true
        if at <= token.offset + token.length {
          break
        }
      }
      NumberToken | TrueToken | FalseToken | NullToken => {
        if !stack.is_empty() {
          let frame = stack[stack.length() - 1]
          if !frame.object || frame.phase != LocKey {
            frame.phase = LocDone
          }
        }
        started = true
        if at <= token.offset + token.length {
          break
        }
      }
      Eof => break
      _ => ()
    }
  }
  if stack.is_empty() {
    return ([], false)
  }
  let path : Array[PathSegment] = []
  for frame in stack {
    path.push(if frame.object { Key(frame.key) } else { Index(frame.index) })
  }
  let frame = stack[stack.length() - 1]
  (path, frame.object && (frame.phase == LocKey || frame.phase == LocColon))
}

///| Find an editor cursor's structural path, including unfinished property slots.

///|
/// Empty Key("") denotes an object key slot; use is_property_key to distinguish it.
/// At a comma or closing bracket offset, the cursor is still before that token.
/// At a property's closing quote and in the gap before its colon, it remains a
/// key position. After the colon it is a value position. Unclosed containers at
/// EOF retain their current key/index slot. This single-prefix scan is linear
/// in source units plus tokens and stores one frame per open container.
pub fn get_location(
  doc : Document,
  offset : Int,
) -> Result[Location, EditError] {
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
      if i + 1 < offset && doc.text.code_unit_at(i + 1) == 10 {
        i += 1
      }
    } else if c == 10 {
      line += 1
      column = 0
    } else {
      column += 1
    }
    i += 1
  }
  let (path, is_property_key) = location_prefix(doc, offset)
  Ok({ path, is_property_key, offset, line, column, })
}

///|
/// Encode a typed path as RFC 6901 JSON Pointer. Numeric object keys stay keys.
pub fn to_pointer(path : Array[PathSegment]) -> String {
  let mut result = ""
  for part in path {
    let value = match part {
      Key(s) => s
      Index(i) => i.to_string()
    }
    result += "/"
    for c in value {
      result += match c {
        '~' => "~0"
        '/' => "~1"
        _ => c.to_string()
      }
    }
  }
  result
}

///|
pub extend Location with Eq::{equal, not_equal}

///|
pub extend Location with @debug.Debug::{to_repr}
