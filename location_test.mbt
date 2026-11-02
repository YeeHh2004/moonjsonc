///|
test "cursor paths distinguish keys, nested values and array insertion slots" {
  let source = "{\"a\": [1, 2], \"b\": true}"
  let doc = @moonjsonc.parse(source)
  let key = @moonjsonc.get_location(doc, 2).unwrap()
  assert_eq(key.path, [@moonjsonc.Key("a")])
  assert_true(key.is_property_key)
  assert_eq(@moonjsonc.get_location(doc, 7).unwrap().path, [
    @moonjsonc.Key("a"),
    @moonjsonc.Index(0),
  ])
  assert_eq(@moonjsonc.get_location(doc, 10).unwrap().path, [
    @moonjsonc.Key("a"),
    @moonjsonc.Index(1),
  ])
  assert_eq(@moonjsonc.get_location(doc, 20).unwrap().path, [
    @moonjsonc.Key("b"),
  ])
  assert_eq(
    @moonjsonc.to_pointer([
      @moonjsonc.Key("a/b~c"),
      @moonjsonc.Index(2),
      @moonjsonc.Key("0"),
    ]),
    "/a~1b~0c/2/0",
  )
}

///|
test "cursor lines count CRLF and UTF16 consistently" {
  let doc = @moonjsonc.parse("{\r\n  \"😀\": 1\r\n}")
  let position = @moonjsonc.get_location(doc, 10).unwrap()
  assert_eq(position.line, 1)
  assert_eq(position.column, 7)
  assert_true(@moonjsonc.get_location(doc, -1) is Err(_))
  assert_true(@moonjsonc.get_location(doc, 100) is Err(_))
}

///|
test "visitor delivers structural comments and literals and allows early stop" {
  let doc = @moonjsonc.parse("{/*note*/\"a\":[1,true]}")
  let kinds : Array[String] = []
  let count = @moonjsonc.visit(doc, event => {
    kinds.push(event.kind)
    true
  })
  assert_eq(count, 10)
  assert_eq(kinds, [
    "object_begin", "comment", "property", "separator", "array_begin", "literal",
    "separator", "literal", "array_end", "object_end",
  ])
  assert_eq(@moonjsonc.visit(doc, _ => false), 1)
}

///|
fn cursor_states(source : String) -> Array[String] {
  let doc = @moonjsonc.parse(source)
  let states : Array[String] = []
  for offset in 0..<(source.length() + 1) {
    let location = @moonjsonc.get_location(doc, offset).unwrap()
    let flag = if location.is_property_key { " K" } else { " V" }
    states.push(@moonjsonc.to_pointer(location.path) + flag)
  }
  states
}

///|
test "cursor every offset distinguishes before and after commas and closing brackets" {
  // Independently checked against jsonc-parser 3.3.1 getLocation at every offset.
  assert_eq(cursor_states("[1,2]"), [" V", "/0 V", "/0 V", "/1 V", "/1 V", " V"])
  assert_eq(cursor_states("{\"a\":1,\"b\":2}"), [
    " V", "/a K", "/a K", "/a K", "/a K", "/a V", "/a V", "/b K", "/b K", "/b K",
    "/b K", "/b V", "/b V", " V",
  ])
  assert_eq(cursor_states("[[]]"), [" V", "/0 V", "/0/0 V", "/0 V", " V"])
}

///|
test "cursor property key state includes closing quote trivia and colon position" {
  assert_eq(cursor_states("{\"a\" : 1}"), [
    " V", "/a K", "/a K", "/a K", "/a K", "/a K", "/a V", "/a V", "/a V", " V",
  ])
  let source = "{\"a\"/* , } : */ \r\n : 1}"
  let doc = @moonjsonc.parse(source)
  let colon = doc.tokens.filter(token => token.kind == Colon)[0]
  for offset in 1..<(colon.offset + 1) {
    let location = @moonjsonc.get_location(doc, offset).unwrap()
    assert_eq(location.path, [@moonjsonc.Key("a")])
    assert_true(location.is_property_key)
  }
  let after = @moonjsonc.get_location(doc, colon.offset + 1).unwrap()
  assert_eq(after.path, [@moonjsonc.Key("a")])
  assert_true(!after.is_property_key)
}

///|
test "cursor unclosed EOF retains candidate key and array insertion paths" {
  for
    (source, expected) in [
      ("", " V"),
      ("/*head*/", " V"),
      ("{", "/ K"),
      ("[", "/0 V"),
      ("{\"a\"", "/a K"),
      ("{\"a\" ", "/a K"),
      ("{\"a\":", "/a V"),
      ("{\"a\":{", "/a/ K"),
      ("{\"a\":[", "/a/0 V"),
      ("{\"a\":[1,", "/a/1 V"),
      ("{\"a\":[1,/* ] , */", "/a/1 V"),
      ("{\"a\":1,", "/ K"),
      ("? {\"a\":[", "/a/0 V"),
    ] {
    assert_eq(cursor_states(source).last().unwrap(), expected)
  }
}

///|
test "cursor key state cannot leak out of an empty or trailing comma object" {
  // The reference leaks isAtPropertyKey=true after the empty object in [ {},"x" ].
  // Our flag always describes the current structural frame instead.
  assert_eq(cursor_states("[{},\"x\"]"), [
    " V", "/0 V", "/0/ K", "/0 V", "/1 V", "/1 V", "/1 V", "/1 V", " V",
  ])
  let source = "{\"a\":{},\"b\":1}"
  let doc = @moonjsonc.parse(source)
  let next_key = doc.tokens.filter(token => {
      token.kind == StringToken && token.value == "b"
    })[0]
  let location = @moonjsonc.get_location(doc, next_key.offset).unwrap()
  assert_eq(location.path, [@moonjsonc.Key("b")])
  assert_true(location.is_property_key)
  for source in ["{}", "{\"a\":1,}", "[{}]", "{\"a\":{}}"] {
    let doc = @moonjsonc.parse(source)
    let end = @moonjsonc.get_location(doc, source.length()).unwrap()
    assert_eq(end.path, [])
    assert_true(!end.is_property_key)
  }
}

///|
test "cursor comment and string punctuation never changes structural state" {
  let source = "{\"a\":\"comma, ] }\"/* , ] } */ , \"b\":0}"
  let doc = @moonjsonc.parse(source)
  let value = doc.tokens.filter(token => {
      token.kind == StringToken && token.value == "comma, ] }"
    })[0]
  let comment = doc.tokens.filter(token => token.kind == BlockComment)[0]
  for offset in value.offset..<(comment.offset + comment.length + 1) {
    let location = @moonjsonc.get_location(doc, offset).unwrap()
    assert_eq(location.path, [@moonjsonc.Key("a")])
    assert_true(!location.is_property_key)
  }
}

///|
test "cursor incomplete deep prefixes and large flat arrays require no tree recursion" {
  let source = String::make(2048, '[')
  let location = @moonjsonc.get_location(
    @moonjsonc.parse(source),
    source.length(),
  ).unwrap()
  assert_eq(location.path.length(), 2048)
  for part in location.path {
    assert_eq(part, @moonjsonc.Index(0))
  }
  assert_true(!location.is_property_key)
  let source = StringBuilder()
  source.write_string("[")
  for index in 0..<5000 {
    if index > 0 {
      source.write_string(",")
    }
    source.write_string("0")
  }
  source.write_string("]")
  let text = source.to_string()
  let doc = @moonjsonc.parse(text)
  assert_eq(@moonjsonc.get_location(doc, text.length() - 1).unwrap().path, [
    @moonjsonc.Index(4999),
  ])
  assert_eq(@moonjsonc.get_location(doc, text.length()).unwrap().path, [])
}
