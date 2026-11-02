///|
/// Connect source positions, structured paths, and diagnostics to an editor.
fn main {
  let doc = @jsonc.parse("{\"editor\":{\"rulers\":[80,100]},}")
  let location = @jsonc.get_location(doc, 22).unwrap()
  println(@jsonc.to_pointer(location.path))
  let count = @jsonc.visit(doc, event => {
    if event.kind == "literal" {
      println(@jsonc.to_pointer(event.path))
    }
    true
  })
  println("visited \{count} source events")
  let partial = @jsonc.parse("{\"editor\": {\"rulers\": [80,")
  println("incomplete document diagnostics: \{partial.diagnostics.length()}")
}
