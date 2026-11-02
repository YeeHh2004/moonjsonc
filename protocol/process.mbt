///|
priv struct Options {
  indentSize : Int?
  useTabs : Bool?
  eol : String?
  finalNewline : Bool?
  allowComments : Bool?
  allowTrailingComma : Bool?
  allowEmpty : Bool?
  maxDepth : Int?
  maxErrors : Int?
} derive(@json.FromJson)

///|
priv struct Range {
  offset : Int
  length : Int
} derive(@json.FromJson)

///|
priv struct Edit {
  offset : Int
  length : Int
  content : String
} derive(@json.FromJson)

///|
priv struct Change {
  op : String
  path : Array[Json]
  value : String?
  index : Int?
} derive(@json.FromJson)

///|
priv struct Request {
  op : String
  source : String
  path : Array[Json]?
  value : String?
  offset : Int?
  index : Int?
  options : Options?
  range : Range?
  operations : Array[Change]?
  edits : Array[Edit]?
  expectedSource : String?
  ignoreTrivia : Bool?
  replaceWithSpaces : Bool?
} derive(@json.FromJson)

///|
fn diagnostics(items : Array[@jsonc.Diagnostic]) -> Json {
  @json.to_json(items.map(d => {
    let result : Json = { "code": d.code, "offset": d.offset, "length": d.length, "message": d.message }
    result
  }))
}

///|
fn failure(error : @jsonc.EditError) -> Json {
  let (code, message, details) = match error {
    InvalidDocument(items) => ("InvalidDocument", "source contains errors; editing refused", diagnostics(items))
    InvalidValue(items) => ("InvalidValue", "replacement must be strict JSON", diagnostics(items))
    InvalidPath(s) => ("InvalidPath", s, Json::null())
    InvalidEdit(s) => ("InvalidEdit", s, Json::null())
    Conflict(s) => ("Conflict", s, Json::null())
    InvalidOptions(s) => ("InvalidOptions", s, Json::null())
  }
  { "ok": false, "code": code, "error": message, "diagnostics": details }
}

///|
fn path_of(value : Array[Json]) -> Result[Array[@jsonc.PathSegment], @jsonc.EditError] {
  if value.length() > 128 { return Err(InvalidPath("path exceeds 128 segments")) }
  let path : Array[@jsonc.PathSegment] = []
  for part in value {
    match part {
      String(s) => path.push(Key(s))
      Number(n, ..) => {
        if n < -1 || n > 2147483647 || n != n.to_int().to_double() {
          return Err(InvalidPath("array index must be a bounded integer"))
        }
        path.push(Index(n.to_int()))
      }
      _ => return Err(InvalidPath("path entries must be string keys or integer indices"))
    }
  }
  Ok(path)
}

///|
fn path_json(path : Array[@jsonc.PathSegment]) -> Json {
  @json.to_json(path.map(p => match p { Key(k) => Json::string(k); Index(i) => @json.to_json(i) }))
}

///|
fn node_json(source : String, node : @jsonc.Node) -> Json {
  let kind = match node.kind {
    ObjectNode => "object"
    ArrayNode => "array"
    PropertyNode => "property"
    StringNode => "string"
    NumberNode => "number"
    BooleanNode => "boolean"
    NullNode => "null"
  }
  let raw = source[node.offset:node.offset + node.length].to_owned()
  let value = if node.kind == NumberNode { Json::string(raw) } else { node.value }
  {
    "kind": kind, "offset": node.offset, "length": node.length, "raw": raw, "value": value,
    "children": @json.to_json(node.children.map(child => node_json(source, child))),
  }
}

///|
fn edits_json(edits : Array[@jsonc.TextEdit]) -> Json {
  @json.to_json(edits.map(e => {
    let result : Json = { "offset": e.offset, "length": e.length, "content": e.content }
    result
  }))
}

///|
fn edited(source : String, result : Result[Array[@jsonc.TextEdit], @jsonc.EditError]) -> Json {
  match result {
    Err(e) => failure(e)
    Ok(edits) => match @jsonc.apply_edits(source, edits) {
      Err(e) => failure(e)
      Ok(text) => { "ok": true, "source": text, "edits": edits_json(edits), "changed": text != source }
    }
  }
}

///| Version 1 JSON transport. Algorithms remain in the MoonBit library.
///| Request <= 2 Mi UTF16 units, source <= 1 Mi, batches <= 128 operations.
pub fn process(text : String) -> String {
  if text.length() > 2097152 { return failure(InvalidOptions("request exceeds 2 Mi UTF-16 units")).stringify() }
  let mut depth = 0
  let mut quoted = false
  let mut escaped = false
  for c in text {
    if quoted {
      if escaped { escaped = false }
      else if c == '\\' { escaped = true }
      else if c == '"' { quoted = false }
    } else if c == '"' { quoted = true }
    else if c == '{' || c == '[' {
      depth += 1
      if depth > 160 { return failure(InvalidOptions("request nesting exceeds 160")).stringify() }
    } else if c == '}' || c == ']' { depth -= 1 }
  }
  let request : Request = @json.from_json(@json.parse(text)) catch {
    _ => return failure(InvalidOptions("invalid JSON request schema")).stringify()
  }
  if request.source.length() > 1048576 { return failure(InvalidOptions("source exceeds 1 Mi UTF-16 units")).stringify() }
  let parse_options : @jsonc.ParseOptions = match request.options {
    None => @jsonc.ParseOptions::default()
    Some(o) => { allow_comments: o.allowComments.unwrap_or(true), allow_trailing_comma: o.allowTrailingComma.unwrap_or(true), allow_empty: o.allowEmpty.unwrap_or(false), max_depth: o.maxDepth.unwrap_or(128), max_errors: o.maxErrors.unwrap_or(100) }
  }
  let format_options : @jsonc.FormatOptions = match request.options {
    None => @jsonc.FormatOptions::default()
    Some(o) => { indent_size: o.indentSize.unwrap_or(2), use_tabs: o.useTabs.unwrap_or(false), eol: o.eol.unwrap_or("\n"), final_newline: o.finalNewline.unwrap_or(false) }
  }
  let path = match path_of(request.path.unwrap_or([])) {
    Ok(p) => p
    Err(e) => return failure(e).stringify()
  }
  let response : Json = match request.op {
    "parse" | "check" => {
      let doc = @jsonc.parse(request.source, options=parse_options)
      { "ok": true, "valid": doc.diagnostics.is_empty(), "diagnostics": diagnostics(doc.diagnostics), "tree": match doc.root { Some(n) => node_json(request.source, n); None => Json::null() } }
    }
    "find" => {
      let doc = @jsonc.parse(request.source, options=parse_options)
      let node = match doc.root { Some(n) => @jsonc.find_node(n, path); None => None }
      { "ok": true, "node": match node { Some(n) => node_json(request.source, n); None => Json::null() }, "diagnostics": diagnostics(doc.diagnostics) }
    }
    "locate" => {
      let doc = @jsonc.parse(request.source, options=parse_options)
      match @jsonc.get_location(doc, request.offset.unwrap_or(0)) {
        Err(e) => failure(e)
        Ok(l) => { "ok": true, "path": path_json(l.path), "pointer": @jsonc.to_pointer(l.path), "isPropertyKey": l.is_property_key, "offset": l.offset, "line": l.line, "column": l.column }
      }
    }
    "visit" => {
      let doc = @jsonc.parse(request.source, options=parse_options)
      let events : Array[Json] = []
      let count = @jsonc.visit(doc, e => {
        events.push({ "kind": e.kind, "offset": e.offset, "length": e.length, "path": path_json(e.path), "value": e.value })
        true
      })
      { "ok": true, "events": @json.to_json(events), "count": count, "diagnostics": diagnostics(doc.diagnostics) }
    }
    "scan" => {
      let tokens = @jsonc.scan(request.source, ignore_trivia=request.ignoreTrivia.unwrap_or(false))
      let items = tokens.map(t => {
        let result : Json = { "kind": token_kind(t.kind), "offset": t.offset, "length": t.length, "value": t.value, "error": @json.to_json(t.error) }
        result
      })
      { "ok": true, "tokens": @json.to_json(items) }
    }
    "strip" => { "ok": true, "source": @jsonc.strip_comments(request.source, replace_with_spaces=request.replaceWithSpaces.unwrap_or(true)) }
    "format" => {
      let range : @jsonc.TextRange? = request.range.map(r => { offset: r.offset, length: r.length })
      edited(request.source, @jsonc.format(request.source, options=format_options, range~))
    }
    "set" => match request.value {
      None => failure(InvalidValue([]))
      Some(value) => edited(request.source, @jsonc.modify(request.source, path, Some(value), options=format_options))
    }
    "remove" => edited(request.source, @jsonc.modify(request.source, path, None, options=format_options))
    "insert" => match request.value {
      None => failure(InvalidValue([]))
      Some(value) => edited(request.source, @jsonc.insert(request.source, path, request.index.unwrap_or(-1), value, options=format_options))
    }
    "apply" => {
      let edits : Array[@jsonc.TextEdit] = request.edits.unwrap_or([]).map(e => { offset: e.offset, length: e.length, content: e.content })
      edited(request.source, Ok(edits))
    }
    "transaction" => {
      let changes = request.operations.unwrap_or([])
      if changes.length() > 128 { return failure(InvalidOptions("batch exceeds 128 operations")).stringify() }
      let operations : Array[@jsonc.Operation] = []
      for change in changes {
        let path = match path_of(change.path) { Ok(p) => p; Err(e) => return failure(e).stringify() }
        let op = match change.op {
          "remove" => @jsonc.Remove(path)
          "set" | "insert" | "test" => {
            let value = match change.value { Some(v) => v; None => return failure(InvalidValue([])).stringify() }
            if change.op == "set" { @jsonc.Set(path, value) }
            else if change.op == "test" { @jsonc.Test(path, value) }
            else { @jsonc.Insert(path, change.index.unwrap_or(-1), value) }
          }
          _ => return failure(InvalidOptions("unknown transaction operation")).stringify()
        }
        operations.push(op)
      }
      match @jsonc.transact(request.source, operations, options=format_options, expected_source=request.expectedSource) {
        Err(e) => failure(e)
        Ok(tx) => { "ok": true, "source": tx.text, "edits": edits_json(tx.edits), "applied": tx.applied, "changed": tx.text != request.source }
      }
    }
    _ => failure(InvalidOptions("unknown operation"))
  }
  response.stringify()
}

///|
fn token_kind(kind : @jsonc.TokenKind) -> String {
  match kind {
    OpenBrace => "OpenBrace"; CloseBrace => "CloseBrace"; OpenBracket => "OpenBracket"; CloseBracket => "CloseBracket"
    Colon => "Colon"; Comma => "Comma"; StringToken => "String"; NumberToken => "Number"
    TrueToken => "True"; FalseToken => "False"; NullToken => "Null"
    LineComment => "LineComment"; BlockComment => "BlockComment"; Whitespace => "Whitespace"; LineBreak => "LineBreak"
    Unknown => "Unknown"; Eof => "Eof"
  }
}
