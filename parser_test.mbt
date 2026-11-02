///|
test "parser JSONC trees retain property structure comments trailing commas and UTF16 spans" {
  let source = "/*h*/{\"a\":[true,{\"😀\":\"x\"}],\"n\":1,}"
  let doc = @moonjsonc.parse(source)
  assert_eq(doc.diagnostics.length(), 0)
  let root = doc.root.unwrap()
  assert_eq(root.kind, @moonjsonc.ObjectNode)
  assert_eq(root.offset, 5)
  assert_eq(root.length, source.length() - 5)
  assert_eq(root.children.length(), 2)
  assert_eq(root.children[0].kind, @moonjsonc.PropertyNode)
  assert_eq(root.children[0].children.length(), 2)
  assert_eq(root.children[0].children[0].value, "a".to_json())
  let nested = @moonjsonc.find_node(root, [
    @moonjsonc.Key("a"),
    @moonjsonc.Index(1),
    @moonjsonc.Key("😀"),
  ]).unwrap()
  assert_eq(nested.value, "x".to_json())
  assert_eq(
    source
    .view(start_offset=nested.offset, end_offset=nested.offset + nested.length)
    .to_owned(),
    "\"x\"",
  )
}

///|
test "parser preserves exact numeric spellings including huge exponents and negative zero" {
  let source = "[9007199254740993,-0,1e400,1e-400,1.2300E+02]"
  let doc = @moonjsonc.parse(source)
  assert_eq(doc.diagnostics.length(), 0)
  let values = doc.root.unwrap().children
  for i, spelling in ["9007199254740993", "-0", "1e400", "1e-400", "1.2300E+02"] {
    let node = values[i]
    assert_eq(
      source
      .view(start_offset=node.offset, end_offset=node.offset + node.length)
      .to_owned(),
      spelling,
    )
    assert_eq(@moonjsonc.node_value(node).stringify(), spelling)
  }
  match values[3].value {
    Number(n, ..) => assert_eq(n, 0.0)
    _ => fail("expected numeric projection")
  }
}

///|
test "parser options independently govern comments trailing commas and empty documents" {
  let strict : @moonjsonc.ParseOptions = {
    ..@moonjsonc.ParseOptions::default(),
    allow_comments: false,
    allow_trailing_comma: false,
  }
  assert_eq(@moonjsonc.parse("[1]", options=strict).diagnostics.length(), 0)
  let errors = @moonjsonc.parse("/*x*/[1,]", options=strict).diagnostics
  assert_true(errors.any(d => d.code == "InvalidCommentToken"))
  assert_true(errors.any(d => d.code == "TrailingComma"))
  assert_true(
    @moonjsonc.parse("//only").diagnostics.any(d => d.code == "ValueExpected"),
  )
  let empty = @moonjsonc.parse("//only", options={
    ..@moonjsonc.ParseOptions::default(),
    allow_empty: true,
  })
  assert_eq(empty.diagnostics.length(), 0)
  assert_true(empty.root is None)
}

///|
test "parser duplicate decoded keys remain visible but query paths are ambiguous" {
  let doc = @moonjsonc.parse("{\"a\":1,\"\\u0061\":2,\"other\":3}")
  assert_true(doc.diagnostics.any(d => d.code == "DuplicateKey"))
  let root = doc.root.unwrap()
  assert_eq(root.children.length(), 3)
  assert_true(@moonjsonc.find_node(root, [@moonjsonc.Key("a")]) is None)
  assert_eq(
    @moonjsonc.find_node(root, [@moonjsonc.Key("other")]).unwrap().value.stringify(),
    "3",
  )
  match @moonjsonc.node_value(root) {
    Object(values) => assert_eq(values["a"].stringify(), "2")
    _ => fail("expected object")
  }
}

///|
test "parser recovers following properties missing separators and malformed lexical values" {
  for
    source in [
      "{\"bad\":,\"ok\":2}", "{\"bad\" 1,\"ok\":2}", "{foo:1,\"ok\":2}", "{\"bad\":1e+,\"ok\":2}",
      "{\"bad\":\"x\n,\"ok\":2}", "{\"bad\":1 \"ok\":2}",
    ] {
    let doc = @moonjsonc.parse(source)
    assert_true(!doc.diagnostics.is_empty())
    let good = @moonjsonc.find_node(doc.root.unwrap(), [@moonjsonc.Key("ok")]).unwrap()
    assert_eq(good.value.stringify(), "2")
  }
  for
    source in [
      "01", "1.", "1e", "-", "true false", "[1,,2]", "{\"x\":[1}", "[{}", "\"\\u12X\"",
      "/*",
    ] {
    assert_true(!@moonjsonc.parse(source).diagnostics.is_empty())
  }
}

///|
test "parser bounded diagnostics and depth prevent pathological recovery recursion" {
  let mut nested = "0"
  for _ in 0..<1000 {
    nested = "[" + nested + "]"
  }
  let doc = @moonjsonc.parse(nested, options={
    ..@moonjsonc.ParseOptions::default(),
    max_depth: 8,
    max_errors: 3,
  })
  assert_true(doc.diagnostics.any(d => d.code == "NestingTooDeep"))
  assert_true(doc.diagnostics.length() <= 3)
  let errors = @moonjsonc.parse(String::make(10000, '?'), options={
    ..@moonjsonc.ParseOptions::default(),
    max_errors: 1,
  })
  assert_eq(errors.diagnostics.length(), 1)
  for depth in [0, 513] {
    assert_eq(
      @moonjsonc.parse("{}", options={
        ..@moonjsonc.ParseOptions::default(),
        max_depth: depth,
      }).diagnostics[0].code,
      "InvalidOptions",
    )
  }
}

///|
test "parser string decoding covers surrogate pairs lone UTF16 units and control escapes" {
  let doc = @moonjsonc.parse(
    "[\"\\uD83D\\uDE00\",\"\\uD800\",\"a\\n\\t\\u0000b\"]",
  )
  assert_eq(doc.diagnostics.length(), 0)
  let values = doc.root.unwrap().children
  assert_eq(values[0].value, "😀".to_json())
  match values[1].value {
    String(s) => assert_eq(s.code_units()[0].to_int(), 0xD800)
    _ => fail("expected string")
  }
  assert_eq(values[2].value, "a\n\t\u0000b".to_json())
}
