///|
test "cursor paths distinguish keys, nested values and array insertion slots" {
  let source = "{\"a\": [1, 2], \"b\": true}"
  let doc = @moonjsonc.parse(source)
  let key = @moonjsonc.get_location(doc, 2).unwrap()
  assert_eq(key.path, [@moonjsonc.Key("a")])
  assert_true(key.is_property_key)
  assert_eq(@moonjsonc.get_location(doc, 7).unwrap().path, [@moonjsonc.Key("a"), @moonjsonc.Index(0)])
  assert_eq(@moonjsonc.get_location(doc, 10).unwrap().path, [@moonjsonc.Key("a"), @moonjsonc.Index(1)])
  assert_eq(@moonjsonc.get_location(doc, 20).unwrap().path, [@moonjsonc.Key("b")])
  assert_eq(@moonjsonc.to_pointer([@moonjsonc.Key("a/b~c"), @moonjsonc.Index(2), @moonjsonc.Key("0")]), "/a~1b~0c/2/0")
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
  let count = @moonjsonc.visit(doc, event => { kinds.push(event.kind); true })
  assert_eq(count, 10)
  assert_eq(kinds, ["object_begin", "comment", "property", "separator", "array_begin", "literal", "separator", "literal", "array_end", "object_end"])
  assert_eq(@moonjsonc.visit(doc, _ => false), 1)
}
