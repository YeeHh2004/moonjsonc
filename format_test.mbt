///|
fn formatted_for_test(
  text : String,
  options? : @moonjsonc.FormatOptions = @moonjsonc.FormatOptions::default(),
  range? : @moonjsonc.TextRange? = None,
) -> String {
  let edits = match @moonjsonc.format(text, options~, range~) {
    Ok(edits) => edits
    Err(_) => abort("unexpected format error")
  }
  match @moonjsonc.apply_edits(text, edits) {
    Ok(output) => output
    Err(_) => abort("unexpected application error")
  }
}

///|
fn raw_tokens_for_test(text : String) -> Array[String] {
  @moonjsonc.scan(text)
  .filter(fn(token) {
    token.kind != Whitespace && token.kind != LineBreak && token.kind != Eof
  })
  .map(fn(token) {
    text
    .view(start_offset=token.offset, end_offset=token.offset + token.length)
    .to_owned()
  })
}

///|
test "format nested objects arrays empty containers and scalar values" {
  assert_eq(
    formatted_for_test(" {\"a\":[1,2],\"empty\":{ },\"b\":true}  "),
    "{\n  \"a\": [\n    1,\n    2\n  ],\n  \"empty\": {},\n  \"b\": true\n}",
  )
  assert_eq(formatted_for_test(" [ ] "), "[]")
  assert_eq(formatted_for_test("  -0.001E+003  "), "-0.001E+003")
}

///|
test "format preserves every nonwhitespace token spelling and order" {
  let text = "/*head*/{\"😀\":1e+02,//tail\r\n\"x\":/*x*/\"\\u0061\",}/*end*/"
  let output = formatted_for_test(text)
  assert_eq(raw_tokens_for_test(output), raw_tokens_for_test(text))
  assert_eq(@moonjsonc.parse(output).diagnostics.length(), 0)
  assert_eq(formatted_for_test(output), output)
}

///|
test "format keeps line comments separate from following syntax" {
  assert_eq(
    formatted_for_test("{\"a\":1,//tail\n\"b\":2}//end"),
    "{\n  \"a\": 1, //tail\n  \"b\": 2\n} //end",
  )
  assert_eq(
    formatted_for_test("[//head\n1//tail\n]"),
    "[\n  //head\n  1 //tail\n]",
  )
}

///|
test "format never rewrites multiline comment content" {
  let text = "{/*a\r\n * b\n */\"x\":1}"
  let output = formatted_for_test(text)
  assert_eq(raw_tokens_for_test(output), raw_tokens_for_test(text))
  assert_eq(formatted_for_test(output), output)
}

///|
test "format supports tabs CRLF final newline and zero indentation" {
  let options : @moonjsonc.FormatOptions = {
    indent_size: 4,
    use_tabs: true,
    eol: "\r\n",
    final_newline: true,
  }
  let output = formatted_for_test("{\"x\":[1]}", options~)
  assert_eq(output, "{\r\n\t\"x\": [\r\n\t\t1\r\n\t]\r\n}\r\n")
  assert_eq(@moonjsonc.format(output, options~), Ok([]))
  let zero : @moonjsonc.FormatOptions = {
    indent_size: 0,
    use_tabs: false,
    eol: "\r",
    final_newline: false,
  }
  assert_eq(formatted_for_test("[1,2]", options=zero), "[\r1,\r2\r]")
}

///|
test "format range expands source lines while preserving all other text" {
  let text = "{\n    \"first\" : 1,\n      \"second\" : 2,\n    \"third\" : 3\n}\n"
  let output = formatted_for_test(text, range=Some({ offset: 28, length: 2, }))
  assert_eq(
    output, "{\n    \"first\" : 1,\n  \"second\": 2,\n    \"third\" : 3\n}\n",
  )
  assert_eq(
    @moonjsonc.format(output, range=Some({ offset: 24, length: 2, })),
    Ok([]),
  )
}

///|
test "format zero length range and CRLF line boundaries are deterministic" {
  let text = "{\r\n    \"a\" : 1,\r\n    \"b\" : 2\r\n}"
  let options : @moonjsonc.FormatOptions = {
    indent_size: 2,
    use_tabs: false,
    eol: "\r\n",
    final_newline: false,
  }
  assert_eq(
    formatted_for_test(text, options~, range=Some({ offset: 9, length: 0, })),
    "{\r\n  \"a\": 1,\r\n    \"b\" : 2\r\n}",
  )
  // A cursor between CR and LF selects their preceding source line.
  assert_eq(
    @moonjsonc.format(text, options~, range=Some({ offset: 2, length: 0, })),
    Ok([]),
  )
}

///|
test "format rejects malformed JSONC and empty input before editing" {
  for text in ["", "/*only*/", "{\"x\":}", "[1,,2]", "{\"x\":\"bad\n\"}"] {
    match @moonjsonc.format(text) {
      Err(InvalidDocument(errors)) => assert_true(!errors.is_empty())
      _ => fail("expected document diagnostics")
    }
  }
}

///|
test "format rejects invalid options and unsafe UTF16 ranges" {
  for size in [-1, 17] {
    let options : @moonjsonc.FormatOptions = {
      indent_size: size,
      use_tabs: false,
      eol: "\n",
      final_newline: false,
    }
    match @moonjsonc.format("{}", options~) {
      Err(InvalidOptions(_)) => ()
      _ => fail("expected invalid indent")
    }
  }
  let options : @moonjsonc.FormatOptions = {
    indent_size: 2,
    use_tabs: false,
    eol: "custom",
    final_newline: false,
  }
  match @moonjsonc.format("{}", options~) {
    Err(InvalidOptions(_)) => ()
    _ => fail("expected invalid eol")
  }
  let ranges : Array[@moonjsonc.TextRange] = [
    { offset: -1, length: 0, },
    { offset: 0, length: -1, },
    { offset: 9, length: 0, },
    { offset: 1, length: 2147483647, },
    { offset: 3, length: 0, },
    { offset: 2, length: 1, },
  ]
  for range in ranges {
    match @moonjsonc.format("{\"😀\":1}", range=Some(range)) {
      Err(InvalidOptions(_)) => ()
      _ => fail("expected invalid range")
    }
  }
}

///|
test "format gap edits are sorted disjoint and preserve semantic value" {
  let corpus = [
    "null", "[1,2,3,]", "{\"a\":[],\"b\":{\"c\":false}}", "[/*x*/1/*y*/,//z\n2]",
    "//start\n{\"x\"/*key*/:/*value*/1}//end", "{\"big\":123456789012345678901234567890,\"tiny\":1e-999}",
  ]
  for text in corpus {
    let edits = @moonjsonc.format(text).unwrap()
    let mut end = 0
    for edit in edits {
      assert_true(edit.offset >= end)
      end = edit.offset + edit.length
      for c in text.view(start_offset=edit.offset, end_offset=end) {
        assert_true(c == ' ' || c == '\t' || c == '\r' || c == '\n')
      }
    }
    let output = @moonjsonc.apply_edits(text, edits).unwrap()
    assert_eq(raw_tokens_for_test(output), raw_tokens_for_test(text))
    assert_eq(
      @moonjsonc.parse(output).root.unwrap().value,
      @moonjsonc.parse(text).root.unwrap().value,
    )
    assert_eq(@moonjsonc.format(output), Ok([]))
  }
}
