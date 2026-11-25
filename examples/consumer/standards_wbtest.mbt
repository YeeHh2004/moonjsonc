///|
test "installed strict JSON API preserves source and distinguishes editing policy" {
  let source = "{\"id\":9007199254740993}"
  let document = @jsonc.parse_json(source).unwrap()
  assert_eq(document.text, source)
  assert_eq(document.root.unwrap().kind, @jsonc.ObjectNode)
  let duplicate = @jsonc.parse_json("{\"a\":1,\"a\":2}").unwrap()
  assert_eq(duplicate.root.unwrap().children.length(), 2)
  assert_true(@jsonc.find_node(duplicate.root.unwrap(), [Key("a")]) is None)
}

///|
test "installed strict JSON API rejects JSONC extensions" {
  match @jsonc.parse_json("[1,]") {
    Err(errors) => {
      assert_eq(errors[0].code, "TrailingComma")
      assert_eq(errors[0].offset, 2)
      assert_eq(errors[0].length, 1)
    }
    Ok(_) => fail("trailing comma must not pass strict JSON")
  }
}
