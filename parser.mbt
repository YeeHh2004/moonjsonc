///|
priv struct JcParser {
  tokens : Array[Token]
  options : ParseOptions
  diagnostics : Array[Diagnostic]
  mut cursor : Int
  mut nodes : Int
}

///|
fn JcParser::issue(
  self : JcParser,
  code : String,
  token : Token,
  message : String,
) -> Unit {
  if self.diagnostics.length() < self.options.max_errors {
    self.diagnostics.push({
      code,
      offset: token.offset,
      length: token.length,
      message,
    })
  }
}

///|
fn JcParser::peek(self : JcParser) -> Token {
  self.tokens[self.cursor]
}

///|
fn JcParser::advance(self : JcParser) -> Token {
  let token = self.peek()
  if token.kind != Eof {
    self.cursor += 1
  }
  token
}

///|
fn jc_leaf(kind : NodeKind, token : Token, value : Json) -> Node {
  { kind, offset: token.offset, length: token.length, value, children: [], }
}

///|
fn JcParser::skip_container(self : JcParser) -> Int {
  let mut depth = 0
  let mut finish = self.peek().offset
  while self.peek().kind != Eof {
    let token = self.advance()
    finish = token.offset + token.length
    match token.kind {
      OpenBrace | OpenBracket => depth += 1
      CloseBrace | CloseBracket => {
        depth -= 1
        if depth <= 0 {
          break
        }
      }
      _ => ()
    }
  }
  finish
}

///|
fn JcParser::value(self : JcParser, depth : Int) -> Node? {
  let token = self.peek()
  self.nodes += 1
  if self.nodes > 100000 {
    self.issue("NodeLimitExceeded", token, "syntax tree exceeds 100000 values")
    while self.peek().kind != Eof {
      self.advance() |> ignore
    }
    return None
  }
  match token.kind {
    OpenBrace | OpenBracket => {
      if depth >= self.options.max_depth {
        self.issue(
          "NestingTooDeep", token, "container nesting exceeds the configured limit",
        )
        let finish = self.skip_container()
        return Some({
          kind: if token.kind == OpenBrace {
            ObjectNode
          } else {
            ArrayNode
          },
          offset: token.offset,
          length: finish - token.offset,
          value: Json::null(),
          children: [],
        })
      }
      Some(self.container(depth + 1, token.kind == OpenBrace))
    }
    StringToken => {
      self.advance() |> ignore
      Some(jc_leaf(StringNode, token, token.value.to_json()))
    }
    NumberToken => {
      self.advance() |> ignore
      let value = if token.error is Some(_) {
        Json::null()
      } else {
        @json.parse(token.value) catch {
          // Number grammar was checked by the lexer. Preserve a valid spelling
          // even beyond Double range; source operations never use this estimate.
          _ =>
            Json::number(
              if token.value.has_prefix("-") {
                -1.0 / 0.0
              } else {
                1.0 / 0.0
              },
              repr=token.value,
            )
        }
      }
      let value = match value {
        Number(estimate, ..) => Json::number(estimate, repr=token.value)
        _ => value
      }
      Some(jc_leaf(NumberNode, token, value))
    }
    TrueToken | FalseToken => {
      self.advance() |> ignore
      Some(jc_leaf(BooleanNode, token, (token.kind == TrueToken).to_json()))
    }
    NullToken => {
      self.advance() |> ignore
      Some(jc_leaf(NullNode, token, Json::null()))
    }
    _ => {
      self.issue("ValueExpected", token, "expected a JSON value")
      None
    }
  }
}

///|
fn JcParser::container(self : JcParser, depth : Int, object : Bool) -> Node {
  let opening = self.advance()
  let closing = if object { CloseBrace } else { CloseBracket }
  let children : Array[Node] = []
  let members : Map[String, Json] = Map([])
  let elements : Array[Json] = []
  while self.peek().kind != Eof &&
        self.peek().kind != CloseBrace &&
        self.peek().kind != CloseBracket {
    if self.peek().kind == Comma {
      let comma = self.advance()
      self.issue(
        if object {
          "PropertyNameExpected"
        } else {
          "ValueExpected"
        },
        comma,
        "unexpected comma",
      )
      continue
    }
    let before = self.cursor
    if object {
      if self.peek().kind != StringToken {
        self.issue(
          "PropertyNameExpected",
          self.peek(),
          "object keys must be quoted strings",
        )
        self.advance() |> ignore
        continue
      }
      let key_token = self.advance()
      let key = jc_leaf(StringNode, key_token, key_token.value.to_json())
      if self.peek().kind == Colon {
        self.advance() |> ignore
      } else {
        self.issue(
          "ColonExpected",
          self.peek(),
          "expected ':' after an object key",
        )
      }
      let value = match self.value(depth) {
        Some(node) => node
        None =>
          {
            kind: NullNode,
            offset: self.peek().offset,
            length: 0,
            value: Json::null(),
            children: [],
          }
      }
      if members.contains(key_token.value) {
        self.issue(
          "DuplicateKey", key_token, "duplicate object key; edits require unambiguous paths",
        )
      }
      members[key_token.value] = value.value
      children.push({
        kind: PropertyNode,
        offset: key.offset,
        length: (value.offset + value.length - key.offset).max(key.length),
        value: value.value,
        children: [key, value],
      })
    } else {
      match self.value(depth) {
        Some(node) => {
          children.push(node)
          elements.push(node.value)
        }
        None => if self.peek().kind != Eof { self.advance() |> ignore }
      }
    }
    if self.cursor == before {
      self.advance() |> ignore
    }
    if self.peek().kind == Comma {
      let comma = self.advance()
      if self.peek().kind == closing && !self.options.allow_trailing_comma {
        self.issue("TrailingComma", comma, "trailing commas are disabled")
      }
    } else if self.peek().kind != closing &&
      self.peek().kind != Eof &&
      self.peek().kind != CloseBrace &&
      self.peek().kind != CloseBracket {
      self.issue("CommaExpected", self.peek(), "expected ',' between values")
    }
  }
  let finish = if self.peek().kind == closing {
    let end = self.advance()
    end.offset + end.length
  } else {
    self.issue(
      if object {
        "CloseBraceExpected"
      } else {
        "CloseBracketExpected"
      },
      self.peek(),
      "container has no matching closing delimiter",
    )
    self.peek().offset
  }
  {
    kind: if object {
      ObjectNode
    } else {
      ArrayNode
    },
    offset: opening.offset,
    length: finish - opening.offset,
    value: if object {
      members.to_json()
    } else {
      elements.to_json()
    },
    children,
  }
}

///|
/// Parse a tolerant, source-positioned JSONC tree. Diagnostics make partial trees
/// unsuitable for mutation. Duplicate keys are retained, diagnosed, and project
/// to last-key-wins Json. Depth is 1..512, diagnostics 1..1000; values <=100000.
pub fn parse(
  text : String,
  options? : ParseOptions = ParseOptions::default(),
) -> Document {
  let tokens = scan(text)
  let diagnostics : Array[Diagnostic] = []
  if options.max_depth < 1 ||
    options.max_depth > 512 ||
    options.max_errors < 1 ||
    options.max_errors > 1000 {
    diagnostics.push({
      code: "InvalidOptions",
      offset: 0,
      length: 0,
      message: "max_depth must be 1..512 and max_errors 1..1000",
    })
    return { text, tokens, root: None, diagnostics, }
  }
  let significant : Array[Token] = []
  let parser : JcParser = {
    tokens: significant,
    options,
    diagnostics,
    cursor: 0,
    nodes: 0,
  }
  for token in tokens {
    if token.error is Some(code) {
      parser.issue(code, token, "invalid JSONC token")
    }
    if token.kind == LineComment || token.kind == BlockComment {
      if !options.allow_comments {
        parser.issue("InvalidCommentToken", token, "comments are disabled")
      }
    }
    // Invalid symbols already have lexical diagnostics. Skipping them here
    // permits useful recovery of the following value instead of discarding an
    // otherwise valid subtree after a typo before the root or a member value.
    if !jc_trivia(token.kind) && token.kind != Unknown {
      significant.push(token)
    }
  }
  let root = if parser.peek().kind == Eof && options.allow_empty {
    None
  } else {
    parser.value(0)
  }
  if root is None && parser.peek().kind != Eof {
    parser.advance() |> ignore
  }
  while parser.peek().kind != Eof {
    parser.issue(
      "EndOfFileExpected",
      parser.advance(),
      "unexpected content after the root value",
    )
  }
  { text, tokens, root, diagnostics, }
}
