///|
// Independent JSON/JSONC lexer. Positions refer to the source's UTF-16 units,
// while scanning and escape decoding use characters without host-side regexes.
priv struct JcScanner {
  source : String
  chars : Array[Char]
  offsets : Array[Int]
  mut cursor : Int
}

///|
fn jc_source_slice(source : String, start : Int, finish : Int) -> String {
  source.view(start_offset=start, end_offset=finish).to_owned()
}

///|
fn jc_trivia(kind : TokenKind) -> Bool {
  match kind {
    Whitespace | LineBreak | LineComment | BlockComment => true
    _ => false
  }
}

///|
fn jc_delimiter(c : Char) -> Bool {
  match c {
    ' ' | '\t' | '\r' | '\n' | '{' | '}' | '[' | ']' | ':' | ',' | '"' | '/' =>
      true
    _ => false
  }
}

///|
fn JcScanner::token(self : JcScanner) -> Token {
  let start = self.cursor
  let c = self.chars[start]
  let mut kind = Unknown
  let mut error : String? = None
  let mut decoded : String? = None
  self.cursor += 1
  match c {
    '{' => kind = OpenBrace
    '}' => kind = CloseBrace
    '[' => kind = OpenBracket
    ']' => kind = CloseBracket
    ':' => kind = Colon
    ',' => kind = Comma
    ' ' | '\t' => {
      kind = Whitespace
      while self.cursor < self.chars.length() &&
            (self.chars[self.cursor] == ' ' || self.chars[self.cursor] == '\t') {
        self.cursor += 1
      }
    }
    '\r' | '\n' => {
      kind = LineBreak
      if c == '\r' &&
        self.cursor < self.chars.length() &&
        self.chars[self.cursor] == '\n' {
        self.cursor += 1
      }
    }
    '/' =>
      if self.cursor < self.chars.length() && self.chars[self.cursor] == '/' {
        kind = LineComment
        self.cursor += 1
        while self.cursor < self.chars.length() &&
              self.chars[self.cursor] != '\r' &&
              self.chars[self.cursor] != '\n' {
          self.cursor += 1
        }
      } else if self.cursor < self.chars.length() &&
        self.chars[self.cursor] == '*' {
        kind = BlockComment
        self.cursor += 1
        let mut closed = false
        while self.cursor < self.chars.length() {
          if self.chars[self.cursor] == '*' &&
            self.cursor + 1 < self.chars.length() &&
            self.chars[self.cursor + 1] == '/' {
            self.cursor += 2
            closed = true
            break
          }
          self.cursor += 1
        }
        if !closed {
          error = Some("UnexpectedEndOfComment")
        }
      } else {
        error = Some("InvalidSymbol")
      }
    '"' => {
      kind = StringToken
      let value : Array[Char] = []
      let mut closed = false
      while self.cursor < self.chars.length() {
        let next = self.chars[self.cursor]
        if next == '"' {
          self.cursor += 1
          closed = true
          break
        }
        if next == '\r' || next == '\n' {
          break
        }
        self.cursor += 1
        if next == '\\' {
          if self.cursor == self.chars.length() {
            break
          }
          let escape = self.chars[self.cursor]
          self.cursor += 1
          match escape {
            '"' | '/' | '\\' => value.push(escape)
            'b' => value.push('\u0008')
            'f' => value.push('\u000C')
            'n' => value.push('\n')
            'r' => value.push('\r')
            't' => value.push('\t')
            'u' => {
              let mut code = 0
              let mut digits = 0
              while digits < 4 && self.cursor < self.chars.length() {
                let ch = self.chars[self.cursor]
                let hex = if ch >= '0' && ch <= '9' {
                  ch.to_int() - 48
                } else if ch >= 'A' && ch <= 'F' {
                  ch.to_int() - 55
                } else if ch >= 'a' && ch <= 'f' {
                  ch.to_int() - 87
                } else {
                  -1
                }
                if hex < 0 {
                  break
                }
                code = code * 16 + hex
                digits += 1
                self.cursor += 1
              }
              if digits == 4 {
                // JSON strings are UTF-16 sequences. Adjacent escaped high/
                // low surrogates combine naturally; lone units remain intact.
                value.push(code.unsafe_to_char())
              } else if error is None {
                error = Some("InvalidUnicode")
              }
            }
            _ => if error is None { error = Some("InvalidEscapeCharacter") }
          }
        } else {
          if next.to_int() < 32 && error is None {
            error = Some("InvalidCharacter")
          }
          value.push(next)
        }
      }
      if !closed && error is None {
        error = Some("UnexpectedEndOfString")
      }
      decoded = Some(String::from_array(value))
    }
    _ =>
      if c.is_ascii_digit() ||
        (
          c == '-' &&
          self.cursor < self.chars.length() &&
          self.chars[self.cursor].is_ascii_digit()
        ) {
        kind = NumberToken
        let first = if c == '-' { self.cursor } else { start }
        self.cursor = first + 1
        if self.chars[first] != '0' {
          while self.cursor < self.chars.length() &&
                self.chars[self.cursor].is_ascii_digit() {
            self.cursor += 1
          }
        }
        if self.cursor < self.chars.length() && self.chars[self.cursor] == '.' {
          self.cursor += 1
          let begin = self.cursor
          while self.cursor < self.chars.length() &&
                self.chars[self.cursor].is_ascii_digit() {
            self.cursor += 1
          }
          if self.cursor == begin {
            error = Some("UnexpectedEndOfNumber")
          }
        }
        if self.cursor < self.chars.length() &&
          (self.chars[self.cursor] == 'e' || self.chars[self.cursor] == 'E') {
          self.cursor += 1
          if self.cursor < self.chars.length() &&
            (self.chars[self.cursor] == '+' || self.chars[self.cursor] == '-') {
            self.cursor += 1
          }
          let begin = self.cursor
          while self.cursor < self.chars.length() &&
                self.chars[self.cursor].is_ascii_digit() {
            self.cursor += 1
          }
          if self.cursor == begin {
            error = Some("UnexpectedEndOfNumber")
          }
        }
      } else {
        while self.cursor < self.chars.length() &&
              !jc_delimiter(self.chars[self.cursor]) {
          self.cursor += 1
        }
        let word = jc_source_slice(
          self.source,
          self.offsets[start],
          self.offsets[self.cursor],
        )
        kind = match word {
          "true" => TrueToken
          "false" => FalseToken
          "null" => NullToken
          _ => Unknown
        }
        if kind == Unknown {
          error = Some("InvalidSymbol")
        }
      }
  }
  let offset = self.offsets[start]
  let finish = self.offsets[self.cursor]
  {
    kind,
    offset,
    length: finish - offset,
    value: decoded.unwrap_or_else(() => {
      jc_source_slice(self.source, offset, finish)
    }),
    error,
  }
}

///|
/// Lex all JSONC tokens, always ending with Eof. Trivia is retained by default.
/// String values are decoded; all other values retain their source spelling.
pub fn scan(text : String, ignore_trivia? : Bool = false) -> Array[Token] {
  let chars = text.to_array()
  let offsets : Array[Int] = []
  let mut offset = 0
  for c in chars {
    offsets.push(offset)
    offset += c.utf16_len()
  }
  offsets.push(offset)
  let scanner : JcScanner = { source: text, chars, offsets, cursor: 0, }
  let tokens : Array[Token] = []
  while scanner.cursor < chars.length() {
    let token = scanner.token()
    if !ignore_trivia || !jc_trivia(token.kind) {
      tokens.push(token)
    }
  }
  tokens.push({
    kind: Eof,
    offset: text.length(),
    length: 0,
    value: "",
    error: None,
  })
  tokens
}
