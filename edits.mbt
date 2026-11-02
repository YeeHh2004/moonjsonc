///|
fn edit_is_boundary(text : String, position : Int) -> Bool {
  if position == 0 || position == text.length() {
    return true
  }
  let before = text.unsafe_get(position - 1)
  let after = text.unsafe_get(position)
  !(before >= 0xD800 && before <= 0xDBFF && after >= 0xDC00 && after <= 0xDFFF)
}

///|
fn edit_slice(text : String, start : Int, end : Int) -> String {
  text[start:end].to_owned()
}

///|
/// Apply independent edits whose offsets refer to the original source. Edits
/// may be supplied in any order; overlapping edits, duplicate insertion points,
/// invalid ranges and boundaries inside a UTF-16 surrogate pair are rejected.
/// The caller's source and edit array are never mutated.
pub fn apply_edits(
  text : String,
  edits : Array[TextEdit],
) -> Result[String, EditError] {
  if edits.length() > 10000 {
    return Err(InvalidEdit("at most 10000 edits may be applied at once"))
  }
  let ordered = edits.copy()
  ordered.sort_by(fn(a, b) {
    if a.offset < b.offset {
      -1
    } else if a.offset > b.offset {
      1
    } else if a.length < b.length {
      -1
    } else if a.length > b.length {
      1
    } else {
      0
    }
  })
  let mut previous_offset = -1
  let mut previous_end = 0
  for edit in ordered {
    if edit.offset < 0 ||
      edit.offset > text.length() ||
      edit.length < 0 ||
      edit.length > text.length() - edit.offset {
      return Err(InvalidEdit("edit range is outside the original source"))
    }
    if edit.offset == previous_offset || edit.offset < previous_end {
      return Err(InvalidEdit("edits overlap or share an insertion position"))
    }
    if !edit_is_boundary(text, edit.offset) ||
      !edit_is_boundary(text, edit.offset + edit.length) {
      return Err(InvalidEdit("edit boundary splits a UTF-16 surrogate pair"))
    }
    previous_offset = edit.offset
    previous_end = edit.offset + edit.length
  }
  let output = StringBuilder()
  let mut position = 0
  for edit in ordered {
    output.write_string(edit_slice(text, position, edit.offset))
    output.write_string(edit.content)
    position = edit.offset + edit.length
  }
  output.write_string(edit_slice(text, position, text.length()))
  Ok(output.to_string())
}
