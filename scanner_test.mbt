///|
test "scanner retains trivia exact spelling and UTF16 source coverage" {
  let text = " {\"😀\":-0.20e+03,/*中*/\"x\":true}\r\n//end"
  let tokens = @moonjsonc.scan(text)
  let mut offset = 0
  for token in tokens {
    assert_eq(token.offset, offset)
    offset += token.length
    assert_eq(token.error, None)
  }
  assert_eq(offset, text.length())
  assert_eq(tokens[2].value, "😀")
  assert_eq(tokens[2].offset, 2)
  assert_eq(tokens[2].length, 4)
  assert_eq(tokens[4].value, "-0.20e+03")
  assert_eq(tokens[tokens.length() - 1].kind, @moonjsonc.Eof)
  for token in @moonjsonc.scan(text, ignore_trivia=true) {
    assert_true(
      token.kind != @moonjsonc.Whitespace &&
      token.kind != @moonjsonc.LineComment &&
      token.kind != @moonjsonc.BlockComment &&
      token.kind != @moonjsonc.LineBreak,
    )
  }
}

///|
test "scanner decodes every JSON escape and preserves surrogate code units" {
  let token = @moonjsonc.scan(
      "\"\\\"\\\\\\/\\b\\f\\n\\r\\t\\u0041\\uD83D\\uDE00\"",
    )[0]
  assert_eq(token.value, "\"\\/\u0008\u000C\n\r\tA😀")
  assert_eq(token.error, None)
  let lone = @moonjsonc.scan("\"\\uD800\"")[0]
  assert_eq(lone.value.length(), 1)
  assert_eq(lone.value.code_units()[0].to_int(), 0xD800)
  assert_eq(lone.error, None)
}

///|
test "scanner reports lexical failures and always makes progress" {
  for
    source in [
      "\"abc", "/*abc", "\"\\u12X\"", "\"\\q\"", "\"a\tb\"", "1.", "1e+", "truefalse",
      "-",
    ] {
    let tokens = @moonjsonc.scan(source)
    assert_true(tokens.any(token => token.error is Some(_)))
    let mut end = 0
    for token in tokens {
      assert_eq(token.offset, end)
      if token.kind != @moonjsonc.Eof {
        assert_true(token.length > 0)
      }
      end += token.length
    }
    assert_eq(end, source.length())
  }
}

///|
test "scanner line errors do not consume following syntax and comments are bounded" {
  let tokens = @moonjsonc.scan("\"broken\n123", ignore_trivia=true)
  assert_eq(tokens[0].kind, @moonjsonc.StringToken)
  assert_eq(tokens[0].value, "broken")
  assert_eq(tokens[0].error, Some("UnexpectedEndOfString"))
  assert_eq(tokens[1].kind, @moonjsonc.NumberToken)
  assert_eq(tokens[1].offset, 8)
  assert_eq(@moonjsonc.scan("/**/")[0].error, None)
  assert_eq(@moonjsonc.scan("/*")[0].error, Some("UnexpectedEndOfComment"))
  assert_eq(@moonjsonc.scan("//x\r\n1")[1].length, 2)
  assert_eq(@moonjsonc.scan("01", ignore_trivia=true)[1].offset, 1)
}
