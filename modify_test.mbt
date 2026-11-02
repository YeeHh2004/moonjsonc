///|
test "replace only the addressed value while retaining exact unrelated source" {
  let source = "// header\r\n{\"a\":1, /* keep */\"big\":9007199254740993}\r\n"
  let edits = @moonjsonc.modify(source, [@moonjsonc.Key("a")], Some("2")).unwrap()
  assert_eq(edits.length(), 1)
  assert_eq(
    @moonjsonc.apply_edits(source, edits),
    Ok("// header\r\n{\"a\":2, /* keep */\"big\":9007199254740993}\r\n"),
  )
  assert_eq(
    @moonjsonc.modify(source, [@moonjsonc.Key("a")], Some("1"))
    .unwrap()
    .length(),
    0,
  )
}

///|
test "append preserves line comments CRLF indentation and closing trivia" {
  let source = "{\r\n  // before\r\n  \"a\": 1 // note\r\n}\r\n"
  let options = { ..@moonjsonc.FormatOptions::default(), eol: "\r\n", }
  let edits = @moonjsonc.modify(
    source,
    [@moonjsonc.Key("b")],
    Some("2"),
    options~,
  ).unwrap()
  assert_eq(
    @moonjsonc.apply_edits(source, edits),
    Ok("{\r\n  // before\r\n  \"a\": 1, // note\r\n  \"b\": 2\r\n}\r\n"),
  )
}

///|
test "removal preserves outside comments and the original trailing comma policy" {
  let source = "{\"a\":1,/*keep*/\"b\":2,\"c\":3}"
  let edits = @moonjsonc.modify(source, [@moonjsonc.Key("b")], None).unwrap()
  assert_eq(
    @moonjsonc.apply_edits(source, edits),
    Ok("{\"a\":1,/*keep*/\"c\":3}"),
  )
  let source = "{\"a\":1,\"b\":2,}"
  assert_eq(
    @moonjsonc.apply_edits(
      source,
      @moonjsonc.modify(source, [@moonjsonc.Key("b")], None).unwrap(),
    ),
    Ok("{\"a\":1,}"),
  )
  let source = "{/*left*/\"a\":1,/*tail*/}"
  assert_eq(
    @moonjsonc.apply_edits(
      source,
      @moonjsonc.modify(source, [@moonjsonc.Key("a")], None).unwrap(),
    ),
    Ok("{/*left*//*tail*/}"),
  )
  assert_eq(
    @moonjsonc.modify("{}", [@moonjsonc.Key("missing")], None).unwrap().length(),
    0,
  )
}

///|
test "array insertion shifts elements and leaves their leading comments intact" {
  let source = "[1,/*two*/2,]"
  let edits = @moonjsonc.insert(source, [], 1, "3").unwrap()
  assert_eq(@moonjsonc.apply_edits(source, edits), Ok("[1, 3,/*two*/2,]"))
  let source = "[\n  // original first\n  1\n]"
  let edits = @moonjsonc.insert(source, [], 0, "2").unwrap()
  assert_eq(
    @moonjsonc.apply_edits(source, edits),
    Ok("[\n  2,\n  // original first\n  1\n]"),
  )
  assert_eq(
    @moonjsonc.insert("[]", [], -1, "2") is Err(@moonjsonc.InvalidPath(_)),
    true,
  )
  assert_eq(
    @moonjsonc.insert("[1]", [], 2, "2") is Err(@moonjsonc.InvalidPath(_)),
    true,
  )
}

///|
test "array append bounds and removal never create sparse null values" {
  let source = "[1,]"
  let edits = @moonjsonc.modify(
    source,
    [@moonjsonc.Index(-1)],
    Some("9007199254740993"),
  ).unwrap()
  assert_eq(@moonjsonc.apply_edits(source, edits), Ok("[1, 9007199254740993,]"))
  assert_eq(
    @moonjsonc.modify("[1]", [@moonjsonc.Index(3)], Some("2"))
    is Err(@moonjsonc.InvalidPath(_)),
    true,
  )
  assert_eq(
    @moonjsonc.modify("[1]", [@moonjsonc.Index(-2)], Some("2"))
    is Err(@moonjsonc.InvalidPath(_)),
    true,
  )
  let source = "[1, /* retained */ 2]"
  let edits = @moonjsonc.modify(source, [@moonjsonc.Index(1)], None).unwrap()
  assert_eq(@moonjsonc.apply_edits(source, edits), Ok("[1 /* retained */ ]"))
}

///|
test "missing parents are created with objects arrays and lossless numbers" {
  let path = [@moonjsonc.Key("a"), @moonjsonc.Index(0), @moonjsonc.Key("b")]
  let result = @moonjsonc.apply_edits(
    "",
    @moonjsonc.modify("", path, Some("9007199254740993")).unwrap(),
  ).unwrap()
  let document = @moonjsonc.parse(result)
  assert_eq(document.diagnostics.length(), 0)
  let node = @moonjsonc.find_node(document.root.unwrap(), path).unwrap()
  assert_eq(
    result[node.offset:node.offset + node.length].to_owned(),
    "9007199254740993",
  )
  assert_eq(
    @moonjsonc.modify(
      "{}",
      [@moonjsonc.Key("a"), @moonjsonc.Index(2)],
      Some("1"),
    )
    is Err(@moonjsonc.InvalidPath(_)),
    true,
  )
  assert_eq(
    @moonjsonc.modify(
      "{\"a\":1}",
      [@moonjsonc.Key("a"), @moonjsonc.Key("b")],
      Some("2"),
    )
    is Err(@moonjsonc.InvalidPath(_)),
    true,
  )
}

///|
test "empty comment documents and escaped Unicode property names are editable" {
  let source = "// note"
  let edits = @moonjsonc.modify(
    source,
    [@moonjsonc.Key("😀\"\\")],
    Some("true"),
  ).unwrap()
  let result = @moonjsonc.apply_edits(source, edits).unwrap()
  assert_eq(result.has_prefix("// note\n"), true)
  let document = @moonjsonc.parse(result)
  assert_eq(document.diagnostics.length(), 0)
  let node = @moonjsonc.find_node(document.root.unwrap(), [
    @moonjsonc.Key("😀\"\\"),
  ]).unwrap()
  assert_eq(node.kind, @moonjsonc.BooleanNode)
  let crlf = @moonjsonc.modify(source, [], Some("1"), options={
    ..@moonjsonc.FormatOptions::default(),
    eol: "\r\n",
  }).unwrap()
  assert_eq(@moonjsonc.apply_edits(source, crlf), Ok("// note\r\n1"))
}

///|
test "invalid documents duplicates non JSON values and invalid options reject atomically" {
  for source in ["{\"a\":}", "{\"a\":1,\"a\":2}", "[1 2]"] {
    assert_eq(
      @moonjsonc.modify(source, [], Some("{}"))
      is Err(@moonjsonc.InvalidDocument(_)),
      true,
    )
  }
  for value in ["", "undefined", "{\"a\":1,}", "/* comment */1", "1 2"] {
    assert_eq(
      @moonjsonc.modify("{}", [@moonjsonc.Key("x")], Some(value))
      is Err(@moonjsonc.InvalidValue(_)),
      true,
    )
  }
  assert_eq(
    @moonjsonc.modify("{}", [], Some("1"), options={
      ..@moonjsonc.FormatOptions::default(),
      indent_size: 100,
    })
    is Err(@moonjsonc.InvalidOptions(_)),
    true,
  )
  assert_eq(
    @moonjsonc.modify("{}", [], Some("1"), options={
      ..@moonjsonc.FormatOptions::default(),
      eol: "x",
    })
    is Err(@moonjsonc.InvalidOptions(_)),
    true,
  )
}
