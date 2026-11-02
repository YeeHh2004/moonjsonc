///|
/// All offsets and lengths are UTF-16 code units, on every backend.
pub(all) enum TokenKind {
  OpenBrace
  CloseBrace
  OpenBracket
  CloseBracket
  Colon
  Comma
  StringToken
  NumberToken
  TrueToken
  FalseToken
  NullToken
  LineComment
  BlockComment
  Whitespace
  LineBreak
  Unknown
  Eof
} derive(Eq, @debug.Debug)

///|
pub(all) struct Token {
  kind : TokenKind
  offset : Int
  length : Int
  value : String
  error : String?
} derive(Eq, @debug.Debug)

///|
pub(all) struct Diagnostic {
  code : String
  offset : Int
  length : Int
  message : String
} derive(Eq, @debug.Debug)

///|
pub(all) enum NodeKind {
  ObjectNode
  ArrayNode
  PropertyNode
  StringNode
  NumberNode
  BooleanNode
  NullNode
} derive(Eq, @debug.Debug)

///| Property children are [key, value]; object children are properties.

///|
/// Scalar value is decoded Json; original numeric spelling stays in source.
pub(all) struct Node {
  kind : NodeKind
  offset : Int
  length : Int
  value : Json
  children : Array[Node]
} derive(@debug.Debug)

///|
pub(all) struct Document {
  text : String
  tokens : Array[Token]
  root : Node?
  diagnostics : Array[Diagnostic]
} derive(@debug.Debug)

///|
pub(all) struct ParseOptions {
  allow_comments : Bool
  allow_trailing_comma : Bool
  allow_empty : Bool
  max_depth : Int
  max_errors : Int
} derive(Eq, @debug.Debug)

///|
pub fn ParseOptions::default() -> ParseOptions {
  {
    allow_comments: true,
    allow_trailing_comma: true,
    allow_empty: false,
    max_depth: 128,
    max_errors: 100,
  }
}

///|
pub(all) enum PathSegment {
  Key(String)
  Index(Int)
} derive(Eq, @debug.Debug)

///|
pub(all) struct TextEdit {
  offset : Int
  length : Int
  content : String
} derive(Eq, @debug.Debug)

///|
pub(all) struct TextRange {
  offset : Int
  length : Int
} derive(Eq, @debug.Debug)

///|
pub(all) struct FormatOptions {
  indent_size : Int
  use_tabs : Bool
  eol : String
  final_newline : Bool
} derive(Eq, @debug.Debug)

///|
pub fn FormatOptions::default() -> FormatOptions {
  { indent_size: 2, use_tabs: false, eol: "\n", final_newline: false, }
}

///|
pub(all) enum EditError {
  InvalidDocument(Array[Diagnostic])
  InvalidValue(Array[Diagnostic])
  InvalidPath(String)
  InvalidEdit(String)
  Conflict(String)
  InvalidOptions(String)
} derive(Eq, @debug.Debug)

///|
/// Values are strict JSON source to preserve exact number spelling.
pub(all) enum Operation {
  Set(Array[PathSegment], String)
  Remove(Array[PathSegment])
  Insert(Array[PathSegment], Int, String)
  Test(Array[PathSegment], String)
} derive(Eq, @debug.Debug)

///|
pub(all) struct Transaction {
  text : String
  edits : Array[TextEdit]
  applied : Int
} derive(Eq, @debug.Debug)

///|
pub extend TokenKind with @debug.Debug::{to_repr}

///|
pub extend TokenKind with Eq::{equal, not_equal}

///|
pub extend Token with @debug.Debug::{to_repr}

///|
pub extend Token with Eq::{equal, not_equal}

///|
pub extend Diagnostic with @debug.Debug::{to_repr}

///|
pub extend Diagnostic with Eq::{equal, not_equal}

///|
pub extend NodeKind with @debug.Debug::{to_repr}

///|
pub extend NodeKind with Eq::{equal, not_equal}

///|
pub extend Node with @debug.Debug::{to_repr}

///|
pub extend Document with @debug.Debug::{to_repr}

///|
pub extend ParseOptions with @debug.Debug::{to_repr}

///|
pub extend ParseOptions with Eq::{equal, not_equal}

///|
pub extend PathSegment with @debug.Debug::{to_repr}

///|
pub extend PathSegment with Eq::{equal, not_equal}

///|
pub extend TextEdit with @debug.Debug::{to_repr}

///|
pub extend TextEdit with Eq::{equal, not_equal}

///|
pub extend TextRange with @debug.Debug::{to_repr}

///|
pub extend TextRange with Eq::{equal, not_equal}

///|
pub extend FormatOptions with @debug.Debug::{to_repr}

///|
pub extend FormatOptions with Eq::{equal, not_equal}

///|
pub extend EditError with @debug.Debug::{to_repr}

///|
pub extend EditError with Eq::{equal, not_equal}

///|
pub extend Operation with @debug.Debug::{to_repr}

///|
pub extend Operation with Eq::{equal, not_equal}

///|
pub extend Transaction with @debug.Debug::{to_repr}

///|
pub extend Transaction with Eq::{equal, not_equal}
