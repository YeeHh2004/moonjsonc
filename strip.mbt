///| Remove comment tokens without interpreting comment-like text in strings.

///| The default replaces each non-newline UTF-16 unit with one ASCII space,

///| preserving source offsets and all CR/LF characters. With false, complete

///|
/// comment tokens (including any internal line breaks) are deleted.
pub fn strip_comments(
  text : String,
  replace_with_spaces? : Bool = true,
) -> String {
  let output = StringBuilder()
  let mut end = 0
  for token in scan(text) {
    match token.kind {
      LineComment | BlockComment => {
        output.write_string(
          text.view(start_offset=end, end_offset=token.offset).to_owned(),
        )
        if replace_with_spaces {
          let body = text.view(
            start_offset=token.offset,
            end_offset=token.offset + token.length,
          )
          for c in body {
            if c == '\r' || c == '\n' {
              output.write_char(c)
            } else {
              output.write_string(String::make(c.utf16_len(), ' '))
            }
          }
        }
        end = token.offset + token.length
      }
      _ => ()
    }
  }
  output.write_string(text.view(start_offset=end).to_owned())
  output.to_string()
}
