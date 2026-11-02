///|
/// Update a package command without touching the comment or exact build identifier.
fn main {
  let source = "{\n  // Team command\n  \"scripts\": {\"test\": \"moon test\"},\n  \"buildId\": 9007199254740993\n}\n"
  let edits = @jsonc.modify(
    source,
    [Key("scripts"), Key("test")],
    Some("\"moon test --target wasm-gc\""),
  ).unwrap()
  println(@jsonc.apply_edits(source, edits).unwrap())
}
