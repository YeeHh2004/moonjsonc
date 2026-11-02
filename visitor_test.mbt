///|
test "visitor refuses deep token streams even when earlier errors fill diagnostic budget" {
  let source = "?" + String::make(2000, '[')
  let doc = @moonjsonc.parse(source, options={
    ..@moonjsonc.ParseOptions::default(),
    max_errors: 1,
  })
  let mut called = false
  let count = @moonjsonc.visit(doc, _ => {
    called = true
    true
  })
  assert_eq(count, 0)
  assert_false(called)
  assert_eq(doc.diagnostics.length(), 1)
}
