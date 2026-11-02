///|
test "transactions sequence dependent edits and return original source coordinates" {
  let source = "// configuration\r\n{\r\n  \"items\": [1, 2],\r\n  \"large\": 9007199254740993\r\n}\r\n"
  let operations = [
    @moonjsonc.Set([@moonjsonc.Key("enabled")], "true"),
    @moonjsonc.Insert([@moonjsonc.Key("items")], 1, "3"),
    @moonjsonc.Set([@moonjsonc.Key("items"), @moonjsonc.Index(0)], "4"),
    @moonjsonc.Remove([@moonjsonc.Key("items"), @moonjsonc.Index(2)]),
    @moonjsonc.Test([@moonjsonc.Key("items")], "[4,3]"),
  ]
  let result = @moonjsonc.transact(
    source,
    operations,
    options={ ..@moonjsonc.FormatOptions::default(), eol: "\r\n", },
    expected_source=Some(source),
  ).unwrap()
  assert_eq(result.applied, 5)
  assert_eq(@moonjsonc.apply_edits(source, result.edits), Ok(result.text))
  assert_eq(result.text.has_prefix("// configuration\r\n"), true)
  assert_eq(result.text.contains("9007199254740993"), true)
  assert_eq(@moonjsonc.parse(result.text).diagnostics.length(), 0)
  let root = @moonjsonc.parse(result.text).root.unwrap()
  assert_eq(
    @moonjsonc.find_node(root, [@moonjsonc.Key("enabled")]).unwrap().kind,
    @moonjsonc.BooleanNode,
  )
  assert_eq(operations.length(), 5)
}

///|
test "failed transactions expose no partial result and expected source is exact" {
  let source = "{\"n\":1}"
  assert_eq(
    @moonjsonc.transact(source, [
      @moonjsonc.Set([@moonjsonc.Key("n")], "2"),
      @moonjsonc.Test([@moonjsonc.Key("n")], "1"),
    ])
    is Err(@moonjsonc.Conflict(_)),
    true,
  )
  assert_eq(source, "{\"n\":1}")
  assert_eq(
    @moonjsonc.transact(source, [], expected_source=Some("{ \"n\":1}"))
    is Err(@moonjsonc.Conflict(_)),
    true,
  )
  assert_eq(
    @moonjsonc.transact(source, [
      @moonjsonc.Set([@moonjsonc.Key("n")], "2"),
      @moonjsonc.Set([@moonjsonc.Key("bad")], "[1,]"),
    ])
    is Err(@moonjsonc.InvalidValue(_)),
    true,
  )
  assert_eq(
    @moonjsonc.transact(source, [
      @moonjsonc.Test([@moonjsonc.Key("missing")], "null"),
    ])
    is Err(@moonjsonc.Conflict(_)),
    true,
  )
}

///|
test "transaction tests compare object content and decoded strings but exact numeric spelling" {
  let source = "{\"value\":{\"b\":[true,\"\\u0061\"],\"a\":9007199254740993}}"
  let result = @moonjsonc.transact(source, [
    @moonjsonc.Test(
      [@moonjsonc.Key("value")],
      "{\"a\":9007199254740993,\"b\":[true,\"a\"]}",
    ),
  ]).unwrap()
  assert_eq(result.text, source)
  assert_eq(result.edits.length(), 0)
  assert_eq(result.applied, 1)
  for
    (actual, expected) in [
      ("1", "1.0"),
      ("1e0", "1"),
      ("-0", "0"),
      ("9007199254740993", "9007199254740992"),
    ] {
    assert_eq(
      @moonjsonc.transact(actual, [@moonjsonc.Test([], expected)])
      is Err(@moonjsonc.Conflict(_)),
      true,
    )
  }
  assert_eq(
    @moonjsonc.transact("[1,2]", [@moonjsonc.Test([], "[2,1]")])
    is Err(@moonjsonc.Conflict(_)),
    true,
  )
}

///|
test "transaction final patches keep UTF16 surrogate boundaries intact" {
  let source = "{\"😀\":\"a😀z\",\"keep\":\"🦋\"}"
  let result = @moonjsonc.transact(source, [
    @moonjsonc.Set([@moonjsonc.Key("😀")], "\"a😃z\""),
    @moonjsonc.Set([@moonjsonc.Key("added")], "\"🍎\""),
  ]).unwrap()
  assert_eq(@moonjsonc.apply_edits(source, result.edits), Ok(result.text))
  assert_eq(result.text.contains("a😃z"), true)
  assert_eq(result.text.contains("🦋"), true)
  assert_eq(@moonjsonc.parse(result.text).diagnostics.length(), 0)
}

///|
test "root removal and recreation can occur atomically while outside comments survive" {
  let source = "/* header */ {\"old\":1} /* trailer */"
  let result = @moonjsonc.transact(source, [
    @moonjsonc.Remove([]),
    @moonjsonc.Set(
      [@moonjsonc.Key("new"), @moonjsonc.Index(0)],
      "9007199254740993",
    ),
    @moonjsonc.Test([@moonjsonc.Key("new")], "[9007199254740993]"),
  ]).unwrap()
  assert_eq(result.text.contains("/* header */"), true)
  assert_eq(result.text.contains("/* trailer */"), true)
  assert_eq(@moonjsonc.apply_edits(source, result.edits), Ok(result.text))
  let empty = @moonjsonc.transact("", [
    @moonjsonc.Remove([@moonjsonc.Key("missing")]),
  ]).unwrap()
  assert_eq(empty.text, "")
  assert_eq(empty.applied, 1)
  assert_eq(empty.edits.length(), 0)
}

///|
test "transactions reject oversized operations invalid paths and invalid starting documents" {
  let operations = Array::make(1001, @moonjsonc.Remove([]))
  assert_eq(
    @moonjsonc.transact("{}", operations) is Err(@moonjsonc.InvalidEdit(_)),
    true,
  )
  assert_eq(
    @moonjsonc.transact("{}", [
      @moonjsonc.Set(Array::make(129, @moonjsonc.Key("deep")), "1"),
    ])
    is Err(@moonjsonc.InvalidPath(_)),
    true,
  )
  assert_eq(
    @moonjsonc.transact("[]", [@moonjsonc.Insert([], -1, "1")])
    is Err(@moonjsonc.InvalidPath(_)),
    true,
  )
  assert_eq(
    @moonjsonc.transact("{}", [@moonjsonc.Remove([@moonjsonc.Index(-2)])])
    is Err(@moonjsonc.InvalidPath(_)),
    true,
  )
  for source in ["{\"duplicate\":1,\"duplicate\":2}", "[1 2]"] {
    assert_eq(
      @moonjsonc.transact(source, []) is Err(@moonjsonc.InvalidDocument(_)),
      true,
    )
  }
}
