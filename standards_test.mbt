///|
test "strict JSON accepts all six types including scalar document roots" {
  for
    (source, kind) in [
      ("null", @moonjsonc.NullNode),
      ("true", @moonjsonc.BooleanNode),
      ("false", @moonjsonc.BooleanNode),
      ("-42.125e+2", @moonjsonc.NumberNode),
      ("\"hello\"", @moonjsonc.StringNode),
      ("[]", @moonjsonc.ArrayNode),
      ("{}", @moonjsonc.ObjectNode),
    ] {
    let document = @moonjsonc.parse_json(source).unwrap()
    assert_eq(document.text, source)
    assert_eq(document.diagnostics.length(), 0)
    assert_eq(document.root.unwrap().kind, kind)
    assert_eq(document.root.unwrap().length, source.length())
  }
  let source = " \t\r\n {\"types\":[null,true,false,-1.25e+2,\"text\",[],{}]} \n"
  let document = @moonjsonc.parse_json(source).unwrap()
  let root = document.root.unwrap()
  assert_eq(root.offset, 5)
  assert_eq(
    @moonjsonc.find_node(root, [@moonjsonc.Key("types")]).unwrap().children.length(),
    7,
  )
}

///|
test "strict JSON decodes Unicode and JSON escapes with UTF16 source spans" {
  let source = "{\"😀\":\"汉字é€𝄞\",\"escaped\":\"\\\"\\\\\\/\\b\\f\\n\\r\\t\\u0000\",\"pair\":\"\\uD83D\\uDE00\"}"
  let root = @moonjsonc.parse_json(source).unwrap().root.unwrap()
  let text = @moonjsonc.find_node(root, [@moonjsonc.Key("😀")]).unwrap()
  assert_eq(text.value, "汉字é€𝄞".to_json())
  assert_eq(text.offset, 6)
  assert_eq(text.length, 8)
  assert_eq(
    source
    .view(start_offset=text.offset, end_offset=text.offset + text.length)
    .to_owned(),
    "\"汉字é€𝄞\"",
  )
  assert_eq(
    @moonjsonc.find_node(root, [@moonjsonc.Key("escaped")]).unwrap().value,
    "\"\\/\u0008\u000C\n\r\t\u0000".to_json(),
  )
  assert_eq(
    @moonjsonc.find_node(root, [@moonjsonc.Key("pair")]).unwrap().value,
    "😀".to_json(),
  )
  // RFC 8259's string grammar also permits escaped unpaired UTF-16 units.
  // Retain them as code units rather than silently replacing or normalizing.
  let lone = @moonjsonc.parse_json("\"\\uDEAD\"").unwrap().root.unwrap()
  match lone.value {
    String(value) => assert_eq(value.code_units()[0].to_int(), 0xDEAD)
    _ => fail("expected a decoded string")
  }
}

///|
test "strict JSON preserves every legal numeric lexeme beyond Double precision and range" {
  for
    source in [
      "0", "-0", "0.0", "-0.000", "9007199254740993", "12345678901234567890123456789012345678901234567890",
      "1e400", "-1E+400", "1e-400", "1e99999999999999999999999999", "1e-99999999999999999999999999",
      "1.230000E+002",
    ] {
    let document = @moonjsonc.parse_json(source).unwrap()
    let root = document.root.unwrap()
    assert_eq(root.kind, @moonjsonc.NumberNode)
    assert_eq(root.offset, 0)
    assert_eq(root.length, source.length())
    assert_eq(@moonjsonc.node_value(root).stringify(), source)
    assert_eq(document.tokens[0].value, source)
  }
}

///|
test "strict JSON rejects JSONC extensions empty documents and non JSON syntax" {
  for
    source in [
      "", " \t\r\n", "// only", "/*only*/", "// before\n{}", "{}// after", "{/*inside*/\"a\":1}",
      "[1,]", "{\"a\":1,}", "{unquoted:1}", "{'a':1}", "[1,,2]", "{\"a\" 1}", "{\"a\":}",
      "[1 2]", "true false", "{}[]", "[}", "[1", "{", "\"unterminated", "\"line\nbreak\"",
      "\"\\x20\"", "\"\\u12X4\"", "\"raw\u0001control\"", "undefined", "NaN", "Infinity",
      "True", "NULL", "+1", ".1", "-.1", "01", "-01", "1.", "1e", "1e+", "0x10",
      "1_000", "-", "\u000Bnull", "\u000Cnull", "\u00A0null", "\uFEFF{}",
    ] {
    match @moonjsonc.parse_json(source) {
      Err(errors) => assert_true(!errors.is_empty())
      Ok(_) => fail("non-JSON text unexpectedly accepted: " + source)
    }
  }
  let source = "/* allowed in JSONC */ {\"a\":1,}"
  assert_eq(@moonjsonc.parse(source).diagnostics.length(), 0)
  assert_true(@moonjsonc.parse_json(source) is Err(_))
}

///|
test "strict JSON accepts duplicate keys without hiding their source or changing editing policy" {
  let source = "{\"a\":1,\"\\u0061\":2,\"a\":{\"last\":true},\"other\":3}"
  let document = @moonjsonc.parse_json(source, max_errors=1).unwrap()
  let root = document.root.unwrap()
  assert_eq(document.diagnostics.length(), 0)
  assert_eq(root.children.length(), 4)
  assert_eq(root.children[0].children[1].value.stringify(), "1")
  assert_eq(root.children[1].children[1].value.stringify(), "2")
  assert_true(@moonjsonc.find_node(root, [@moonjsonc.Key("a")]) is None)
  assert_eq(
    @moonjsonc.find_node(root, [@moonjsonc.Key("other")]).unwrap().value.stringify(),
    "3",
  )
  match @moonjsonc.node_value(root) {
    Object(values) => assert_eq(values["a"].stringify(), "{\"last\":true}")
    _ => fail("expected object projection")
  }
  assert_true(
    @moonjsonc.parse(source).diagnostics.any(d => d.code == "DuplicateKey"),
  )
  assert_true(
    @moonjsonc.modify(source, [@moonjsonc.Key("a")], Some("4"))
    is Err(@moonjsonc.InvalidDocument(_)),
  )
  assert_true(@moonjsonc.format(source) is Err(@moonjsonc.InvalidDocument(_)))
}

///|
test "duplicate keys never exhaust strict JSON diagnostics before a later syntax error" {
  for
    (source, expected) in [
      ("{\"a\":1,\"a\":2,\"broken\":}", "ValueExpected"),
      ("{\"a\":1,\"a\":2,\"broken\" 3}", "ColonExpected"),
      ("{\"a\":1,\"a\":2 \"b\":3}", "CommaExpected"),
      ("{\"a\":1,\"a\":2,}", "TrailingComma"),
      ("{\"a\":1,\"a\":2} false", "EndOfFileExpected"),
      ("{\"a\":1,\"a\":2,\"child\":[1,]}", "TrailingComma"),
    ] {
    match @moonjsonc.parse_json(source, max_errors=1) {
      Err(errors) => {
        assert_eq(errors.length(), 1)
        assert_eq(errors[0].code, expected)
      }
      Ok(_) => fail("syntax error hidden by a preceding duplicate key")
    }
  }
  let out = StringBuilder()
  out.write_string("{\"a\":0")
  for _ in 0..<150 {
    out.write_string(",\"a\":1")
  }
  out.write_string("}")
  let valid = out.to_string()
  assert_eq(
    @moonjsonc.parse_json(valid, max_errors=1).unwrap().root.unwrap().children.length(),
    151,
  )
  match @moonjsonc.parse_json(valid + " []", max_errors=1) {
    Err(errors) => assert_eq(errors[0].code, "EndOfFileExpected")
    Ok(_) => fail("duplicate keys must not consume a syntax-error budget")
  }
}

///|
test "strict JSON validates configuration limits and exact nesting boundaries" {
  for depth in [-1, 0, 513] {
    match @moonjsonc.parse_json("{}", max_depth=depth) {
      Err(errors) => assert_eq(errors[0].code, "InvalidOptions")
      Ok(_) => fail("invalid nesting configuration accepted")
    }
  }
  for count in [-1, 0, 1001] {
    match @moonjsonc.parse_json("{}", max_errors=count) {
      Err(errors) => assert_eq(errors[0].code, "InvalidOptions")
      Ok(_) => fail("invalid error configuration accepted")
    }
  }
  assert_true(@moonjsonc.parse_json("[]", max_depth=1) is Ok(_))
  assert_true(@moonjsonc.parse_json("[0]", max_depth=1) is Ok(_))
  match @moonjsonc.parse_json("[[]]", max_depth=1) {
    Err(errors) => assert_eq(errors[0].code, "NestingTooDeep")
    Ok(_) => fail("configured depth exceeded")
  }
  let mut nested = "0"
  for _ in 0..<512 {
    nested = "[" + nested + "]"
  }
  assert_true(
    @moonjsonc.parse_json(nested, max_depth=512, max_errors=1000) is Ok(_),
  )
  match @moonjsonc.parse_json("[" + nested + "]", max_depth=512, max_errors=1) {
    Err(errors) => assert_eq(errors[0].code, "NestingTooDeep")
    Ok(_) => fail("maximum nesting exceeded")
  }
  let bad = "[" + String::make(20000, ',') + "]"
  match @moonjsonc.parse_json(bad, max_errors=3) {
    Err(errors) => {
      assert_eq(errors.length(), 3)
      for diagnostic in errors {
        assert_true(diagnostic.offset >= 0 && diagnostic.length >= 0)
        assert_true(diagnostic.offset + diagnostic.length <= bad.length())
      }
    }
    Ok(_) => fail("invalid array unexpectedly accepted")
  }
}

///|
test "strict JSON returns a resource error instead of accepting a truncated tree" {
  let out = StringBuilder()
  out.write_string("[0")
  for _ in 0..<99999 {
    out.write_string(",0")
  }
  out.write_string("]")
  // 100000 array elements plus the container exceed the existing value cap.
  match @moonjsonc.parse_json(out.to_string(), max_errors=1) {
    Err(errors) => assert_eq(errors[0].code, "NodeLimitExceeded")
    Ok(_) => fail("node resource limit was silently ignored")
  }
}

///|
test "whitespace formatting of strict JSON keeps strict validity and exact token spelling" {
  let source = "{\"text\":\"\\u4e2d文😀\",\"types\":[null,true,false,{},[]],\"numbers\":[-0,9007199254740993,1e400,1.2300E+02]}"
  assert_true(@moonjsonc.parse_json(source) is Ok(_))
  for
    options in [
      @moonjsonc.FormatOptions::default(),
      {
        ..@moonjsonc.FormatOptions::default(),
        use_tabs: true,
        eol: "\r\n",
        final_newline: true,
      },
    ] {
    let formatted = @moonjsonc.apply_edits(
      source,
      @moonjsonc.format(source, options~).unwrap(),
    ).unwrap()
    assert_true(@moonjsonc.parse_json(formatted) is Ok(_))
    let before = @moonjsonc.scan(source, ignore_trivia=true).map(t => {
      source
      .view(start_offset=t.offset, end_offset=t.offset + t.length)
      .to_owned()
    })
    let after = @moonjsonc.scan(formatted, ignore_trivia=true).map(t => {
      formatted
      .view(start_offset=t.offset, end_offset=t.offset + t.length)
      .to_owned()
    })
    assert_eq(after, before)
  }
}
