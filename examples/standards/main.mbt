///|
/// Run with: moon run examples/standards --target js (or --target wasm-gc).
/// No host JSON parser or JavaScript runtime API is used by this example.
fn main {
  let source = "{\"message\":\"中文😀\",\"values\":[null,true,false,\"text\",{},[]],\"numbers\":[-0,9007199254740993,1e400]}"
  let document = @jsonc.parse_json(source).unwrap()
  println(
    "Strict JSON accepted: " +
    document.root.unwrap().children.length().to_string() +
    " properties",
  )
  let edits = @jsonc.format(source).unwrap()
  let formatted = @jsonc.apply_edits(source, edits).unwrap()
  // Formatting changes whitespace only. Revalidate the generated JSON.
  ignore(@jsonc.parse_json(formatted).unwrap())
  println(formatted)

  // Root scalars are JSON texts too; keep the original numeric spelling.
  let scalar = @jsonc.parse_json("1e400").unwrap().root.unwrap()
  println("Exact numeric JSON: " + @jsonc.node_value(scalar).stringify())
  match @jsonc.parse_json("/* comment */ [1,]") {
    Err(errors) =>
      println(
        "JSONC extensions rejected: " +
        errors.length().to_string() +
        " diagnostics",
      )
    Ok(_) => abort("strict parsing must reject comments and trailing commas")
  }

  // Duplicate names are syntactically valid JSON. The source tree keeps both
  // properties, while the value projection uses the last property.
  let duplicate = @jsonc.parse_json("{\"a\":1,\"a\":2}").unwrap().root.unwrap()
  println(
    "Retained duplicate properties: " + duplicate.children.length().to_string(),
  )
  println(
    "Last-key-wins projection: " + @jsonc.node_value(duplicate).stringify(),
  )
  match @jsonc.find_node(duplicate, [Key("a")]) {
    None =>
      println(
        "Ambiguous path refused; the existing editor policy remains unchanged.",
      )
    Some(_) => abort("duplicate paths must remain ambiguous")
  }
}
