///|
test "independent edits use original coordinates and preserve their input array" {
  let edits : Array[@moonjsonc.TextEdit] = [
    { offset: 4, length: 1, content: "X" },
    { offset: 1, length: 2, content: "YZ" },
  ]
  assert_eq(@moonjsonc.apply_edits("abcdef", edits), Ok("aYZdXf"))
  assert_eq(edits[0].offset, 4)
  assert_eq(@moonjsonc.apply_edits("abc", []), Ok("abc"))
  assert_eq(@moonjsonc.apply_edits("", [{offset:0,length:0,content:"{}"}]), Ok("{}"))
}

///|
test "overlap duplicate insertion points and hostile ranges are rejected" {
  assert_eq(@moonjsonc.apply_edits("abcd", [
    {offset:0,length:3,content:"x"}, {offset:2,length:1,content:"y"},
  ]) is Err(@moonjsonc.InvalidEdit(_)), true)
  assert_eq(@moonjsonc.apply_edits("abcd", [
    {offset:2,length:0,content:"x"}, {offset:2,length:0,content:"y"},
  ]) is Err(@moonjsonc.InvalidEdit(_)), true)
  let hostile : Array[@moonjsonc.TextEdit] = [
    {offset:-1,length:1,content:""}, {offset:0,length:-1,content:""},
    {offset:4,length:1,content:""}, {offset:2147483647,length:2147483647,content:""},
  ]
  for edit in hostile {
    assert_eq(@moonjsonc.apply_edits("abcd", [edit]) is Err(@moonjsonc.InvalidEdit(_)), true)
  }
  assert_eq(@moonjsonc.apply_edits("abcd", [
    {offset:1,length:1,content:"X"}, {offset:2,length:0,content:"Y"},
  ]), Ok("aXYcd"))
}

///|
test "edit positions are UTF16 and cannot bisect an emoji" {
  assert_eq(@moonjsonc.apply_edits("a😀b", [{offset:1,length:2,content:"你"}]), Ok("a你b"))
  assert_eq(@moonjsonc.apply_edits("a😀b", [{offset:2,length:0,content:"x"}]) is Err(@moonjsonc.InvalidEdit(_)), true)
  assert_eq(@moonjsonc.apply_edits("a😀b", [{offset:1,length:1,content:"x"}]) is Err(@moonjsonc.InvalidEdit(_)), true)
  assert_eq(@moonjsonc.apply_edits("a😀b", [{offset:3,length:0,content:"x"}]), Ok("a😀xb"))
}

///|
test "edits preserve unrelated comments line endings and numeric spelling" {
  let source = "// note\r\n{\"n\":9007199254740993,\"name\":\"old\"}\r\n"
  let offset = source.length() - 8
  assert_eq(@moonjsonc.apply_edits(source, [{offset,length:5,content:"\"new\""}]),
    Ok("// note\r\n{\"n\":9007199254740993,\"name\":\"new\"}\r\n"))
}
