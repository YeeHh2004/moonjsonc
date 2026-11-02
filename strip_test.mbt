///|
test "stripping preserves strings, Unicode source offsets and line endings" {
  let text = "{\"url\":\"https://a/*b*/\",/*😀*/\"x\":1}//end\r\n"
  let stripped = @moonjsonc.strip_comments(text)
  assert_eq(stripped, "{\"url\":\"https://a/*b*/\",      \"x\":1}     \r\n")
  assert_eq(stripped.length(), text.length())
  assert_eq(@moonjsonc.strip_comments(stripped), stripped)
}

///|
test "stripping a block comment preserves each CR LF in offset mode" {
  assert_eq(@moonjsonc.strip_comments("1/*a\r\nb\nc\rd*/"), "1   \r\n \n \r   ")
}

///|
test "deletion mode removes complete comment tokens only" {
  assert_eq(
    @moonjsonc.strip_comments(
      "/*head\r\n*/{\"x\":/*mid*/1}//tail\n",
      replace_with_spaces=false,
    ),
    "{\"x\":1}\n",
  )
  assert_eq(
    @moonjsonc.strip_comments("\"escaped \\\" // text\""),
    "\"escaped \\\" // text\"",
  )
}

///|
test "stripping is safe for empty input and incomplete comments" {
  assert_eq(@moonjsonc.strip_comments(""), "")
  assert_eq(@moonjsonc.strip_comments("/*missing close"), "               ")
  assert_eq(@moonjsonc.strip_comments("//"), "  ")
  assert_eq(
    @moonjsonc.strip_comments("{\"s\":\"/*unterminated\"}"),
    "{\"s\":\"/*unterminated\"}",
  )
}
