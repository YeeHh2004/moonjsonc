///|
/// Check deployment version and stage a coherent update in memory.
fn main {
  let source = "{/* operations-owned */\"version\":3,\"regions\":[\"east\"]}"
  let operations : Array[@jsonc.Operation] = [
    Test([Key("version")], "3"),
    Set([Key("version")], "4"),
    Insert([Key("regions")], 1, "\"west\""),
  ]
  let result = @jsonc.transact(source, operations, expected_source=Some(source)).unwrap()
  println(result.text)
  let failed = @jsonc.transact(source, [
    Set([Key("version")], "4"),
    Test([Key("version")], "3"),
  ])
  println(
    if failed is Err(_) {
      "conflict: original remains unchanged"
    } else {
      "unexpected success"
    },
  )
}
