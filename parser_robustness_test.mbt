///|
test "robustness unknown prefixes preserve later syntax and remain invalid" {
  for
    (source, kind, offset) in [
      ("? {\"ok\":2}", @moonjsonc.ObjectNode, 2),
      ("NaN [1]", @moonjsonc.ArrayNode, 4),
      ("--1", @moonjsonc.NumberNode, 1),
      ("-true", @moonjsonc.BooleanNode, 1),
    ] {
    let doc = @moonjsonc.parse(source)
    assert_true(doc.diagnostics.any(d => d.code == "InvalidSymbol"))
    let root = doc.root.unwrap()
    assert_eq(root.kind, kind)
    assert_eq(root.offset, offset)
    assert_eq(doc.tokens[0].kind, @moonjsonc.Unknown)
    assert_true(@moonjsonc.modify(source, [], Some("null")) is Err(_))
  }
  let doc = @moonjsonc.parse("{\"x\":? 1,\"ok\":2}")
  assert_eq(
    @moonjsonc.find_node(doc.root.unwrap(), [@moonjsonc.Key("x")]).unwrap().value.stringify(),
    "1",
  )
}

///|
test "robustness massive syntax errors have bounded diagnostics and valid source ranges" {
  let text = "[" + String::make(20000, ',') + "]"
  let doc = @moonjsonc.parse(text, options={
    ..@moonjsonc.ParseOptions::default(),
    max_errors: 7,
  })
  assert_eq(doc.diagnostics.length(), 7)
  assert_eq(doc.root.unwrap().length, text.length())
  for error in doc.diagnostics {
    assert_true(error.offset >= 0 && error.length >= 0)
    assert_true(error.offset + error.length <= text.length())
  }
  let bad = "?\r\n?\r?\n?"
  let bounded = @moonjsonc.parse(bad, options={
    ..@moonjsonc.ParseOptions::default(),
    max_errors: 2,
  })
  assert_eq(bounded.diagnostics.length(), 2)
  assert_true(bounded.root is None)
}

///|
test "robustness excessive nesting is skipped iteratively even at the maximum supported depth" {
  let mut text = "0"
  for _ in 0..<2000 {
    text = "[" + text + "]"
  }
  let doc = @moonjsonc.parse(text, options={
    ..@moonjsonc.ParseOptions::default(),
    max_depth: 512,
    max_errors: 4,
  })
  assert_true(doc.diagnostics.any(d => d.code == "NestingTooDeep"))
  assert_true(doc.diagnostics.length() <= 4)
  assert_eq(doc.root.unwrap().length, text.length())
  assert_eq(
    @moonjsonc.parse("[]", options={
      ..@moonjsonc.ParseOptions::default(),
      max_depth: 513,
    }).diagnostics[0].code,
    "InvalidOptions",
  )
}

///|
test "robustness duplicate keys recovered after a missing value never become editable" {
  let source = "{\"broken\":,\"a\":1,\"\\u0061\":2}"
  let doc = @moonjsonc.parse(source)
  assert_true(doc.diagnostics.any(d => d.code == "ValueExpected"))
  assert_true(doc.diagnostics.any(d => d.code == "DuplicateKey"))
  assert_eq(doc.root.unwrap().children.length(), 3)
  assert_true(
    @moonjsonc.find_node(doc.root.unwrap(), [@moonjsonc.Key("a")]) is None,
  )
  match @moonjsonc.modify(source, [@moonjsonc.Key("a")], Some("3")) {
    Err(@moonjsonc.InvalidDocument(errors)) =>
      assert_true(errors.any(d => d.code == "DuplicateKey"))
    _ => fail("ambiguous partial documents must not produce edits")
  }
}

///|
test "robustness lone surrogate escapes preserve UTF16 keys values and exact spans" {
  let source = "{\"\\uD800\":\"\\uDC00\",\"😀\":\"𝄞\"}"
  let doc = @moonjsonc.parse(source)
  assert_eq(doc.diagnostics.length(), 0)
  let root = doc.root.unwrap()
  let property = root.children[0]
  assert_eq(property.children[0].offset, 1)
  assert_eq(property.children[0].length, 8)
  assert_eq(property.children[1].offset, 10)
  assert_eq(property.children[1].length, 8)
  let surrogate = 0xD800
  let key = String::from_array([surrogate.unsafe_to_char()])
  let value = @moonjsonc.find_node(root, [@moonjsonc.Key(key)]).unwrap()
  match value.value {
    String(s) => assert_eq(s.code_units()[0].to_int(), 0xDC00)
    _ => fail("expected decoded UTF16 string")
  }
  assert_eq(
    @moonjsonc.node_at_offset(root, 5).unwrap().kind,
    @moonjsonc.StringNode,
  )
  assert_eq(
    @moonjsonc.find_node(root, [@moonjsonc.Key("😀")]).unwrap().value,
    "𝄞".to_json(),
  )
}

///|
test "robustness CRLF and astral prefixes do not shift malformed number diagnostics" {
  let source = "{\r\n\"😀\": 1.2.3,\r\n\"b\": -0,\r\n}"
  let doc = @moonjsonc.parse(source)
  let invalid = doc.diagnostics.filter(d => d.code == "InvalidSymbol")
  assert_eq(invalid.length(), 1)
  assert_eq(invalid[0].offset, 12)
  assert_eq(invalid[0].length, 2)
  let b = @moonjsonc.find_node(doc.root.unwrap(), [@moonjsonc.Key("b")]).unwrap()
  assert_eq(b.offset, 22)
  assert_eq(b.length, 2)
  assert_eq(b.value.stringify(), "-0")
  let tokens = @moonjsonc.scan("\"unfinished\r\ntrue")
  assert_eq(tokens[0].error, Some("UnexpectedEndOfString"))
  assert_eq(tokens[1].kind, @moonjsonc.LineBreak)
  assert_eq(tokens[1].offset, 11)
  assert_eq(tokens[1].length, 2)
  assert_eq(tokens[2].offset, 13)
}

///|
test "robustness illegal numbers are diagnosed while legal wide magnitudes retain source" {
  for
    source in [
      "1.2.3", "1e", "01", "-", "-.1", "0x10", "1e+", "NaN", "Infinity", "+1", "1_000",
    ] {
    assert_true(!@moonjsonc.parse(source).diagnostics.is_empty())
  }
  for source in ["0", "-0", "1e400", "-1e400", "1e-400", "1E+3", "0.0"] {
    let doc = @moonjsonc.parse(source)
    assert_eq(doc.diagnostics.length(), 0)
    assert_eq(doc.root.unwrap().value.stringify(), source)
  }
}

///|
test "robustness zero error budgets are explicit configuration errors instead of silent validity" {
  for source in ["{}", "?", ""] {
    let doc = @moonjsonc.parse(source, options={
      ..@moonjsonc.ParseOptions::default(),
      max_errors: 0,
      allow_empty: true,
    })
    assert_eq(doc.diagnostics.length(), 1)
    assert_eq(doc.diagnostics[0].code, "InvalidOptions")
    assert_true(doc.root is None)
  }
}
