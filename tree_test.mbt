///|
test "tree navigation distinguishes keys indices empty paths and absent values" {
  let root = @moonjsonc.parse("{\"\":[null, false, {\"a/b~c\":\"ok\"}]}").root.unwrap()
  assert_eq(@moonjsonc.find_node(root, []).unwrap().offset, root.offset)
  assert_eq(
    @moonjsonc.find_node(root, [@moonjsonc.Key(""), @moonjsonc.Index(0)]).unwrap().kind,
    @moonjsonc.NullNode,
  )
  assert_eq(
    @moonjsonc.find_node(root, [
      @moonjsonc.Key(""),
      @moonjsonc.Index(2),
      @moonjsonc.Key("a/b~c"),
    ]).unwrap().value,
    "ok".to_json(),
  )
  for
    path in [
      [@moonjsonc.Index(0)],
      [@moonjsonc.Key("missing")],
      [@moonjsonc.Key(""), @moonjsonc.Index(-1)],
      [@moonjsonc.Key(""), @moonjsonc.Index(3)],
      [@moonjsonc.Key(""), @moonjsonc.Index(0), @moonjsonc.Key("a")],
    ] {
    assert_true(@moonjsonc.find_node(root, path) is None)
  }
}

///|
test "tree offset lookup returns deepest key value or enclosing syntax region" {
  let root = @moonjsonc.parse("{\"😀\": [12]}").root.unwrap()
  assert_eq(
    @moonjsonc.node_at_offset(root, 2).unwrap().kind,
    @moonjsonc.StringNode,
  )
  assert_eq(
    @moonjsonc.node_at_offset(root, 5).unwrap().kind,
    @moonjsonc.PropertyNode,
  )
  assert_eq(
    @moonjsonc.node_at_offset(root, 8).unwrap().kind,
    @moonjsonc.NumberNode,
  )
  assert_eq(
    @moonjsonc.node_at_offset(root, 10).unwrap().kind,
    @moonjsonc.ArrayNode,
  )
  assert_true(@moonjsonc.node_at_offset(root, -1) is None)
  assert_true(@moonjsonc.node_at_offset(root, root.length) is None)
  assert_eq(
    @moonjsonc.node_at_offset(root, root.length, include_right_bound=true).unwrap().kind,
    @moonjsonc.ObjectNode,
  )
}
