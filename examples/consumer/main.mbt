///|
fn main {
  let text = "{/* keep */\"enabled\":false,\"id\":9007199254740993}"
  let edits = @jsonc.modify(text, [Key("enabled")], Some("true")).unwrap()
  let updated = @jsonc.apply_edits(text, edits).unwrap()
  println(updated)
  println(@jsonc.parse(updated).diagnostics.length())
}
