# Behavior contract

All source offsets, lengths, cursor columns and edit ranges use **UTF-16 code
units**, including the Wasm GC backend. They are not UTF-8 byte offsets or Unicode
scalar counts. Lines and columns are zero-based. Paths distinguish `Key("0")`
from `Index(0)`; the JavaScript transport uses `"0"` versus `0`.

## Parsing and inspection

`scan` returns source-ordered tokens and an EOF token. String values are decoded;
number spellings and comment text remain available. `ignore_trivia=true` omits
whitespace and comments, including their token-level errors; use `parse` for
complete document diagnostics. `parse` defaults to JSONC comments and trailing
commas, rejects an empty document, and retains partial syntax trees on errors.
Turn extensions off with `ParseOptions` for strict JSON validation.

Objects contain `PropertyNode` children, each with a string key and a value
child where recovery found a value. Arrays contain value children. Root and
children carry original source spans. Treat returned documents and their arrays
as immutable snapshots. Query/visitor APIs expect structures returned by this
parser, not arbitrarily assembled or mutated nodes.

Duplicate properties are retained in the tree and diagnosed as `DuplicateKey`.
`node_value` projects them using the last value. `find_node` returns `None` for
ambiguous keys. Editing refuses any document with diagnostics.

Numbers retain their original lexeme, including `-0`, `9007199254740993`, and
`1e400`. `node_value` exposes core `Json`, whose numeric arithmetic uses Double;
its preserved number representation is suitable for serialization, not exact
arithmetic. Source editing never round-trips untouched values through Double.
The JSON transport exposes number-node `value` as the original **string**.

`get_location` resolves an editor cursor into a typed path. `is_property_key`
distinguishes object key slots; `Key("")` can denote an unfinished key slot.
The cursor is between code units: a comma, colon or closing delimiter changes
the context only after the cursor passes it. Key context therefore persists
after its closing quote and through trivia until the cursor passes the colon.
`node_at_offset` locates existing syntax, while cursor lookup also describes
insertion positions. `visit` emits source-ordered object/array begin/end,
property, literal, separator, comment and unknown events. Returning false stops
delivery. It does not implement per-subtree pruning or a streaming reader.
Diagnostics are read from the document separately. Visitor traversal is linear
in token count apart from copying paths (bounded by nesting depth).
Raw token nesting above 512 is refused before event delivery (`visit` returns
zero); this prevents a malformed stream from bypassing the parser's tree-depth
limit. The JSON transport additionally caps visitor responses at 20,000 source
tokens; direct MoonBit callers can stream events through their callback.

## Structural editing

- `modify(source, path, Some(strict_json))` inserts or replaces; `None` removes.
  An empty path addresses the root. Replacements are validated and formatted
  using the supplied options; their numeric lexemes remain unchanged.
- Missing parents are inferred from typed path segments. Existing scalar
  parents are never silently converted to objects or arrays.
- Array set supports existing indices, `length`, and `-1` for append. It does
  not create sparse arrays or fill gaps with null. `insert` accepts `0..length`.
- A missing removal is a no-op; wrong container types and invalid indices are
  errors. Empty or comment-only source can be initialized; root removal leaves
  surrounding comments/whitespace and no value.
- Replacement changes the selected value range only. Insertion adds necessary
  key/value/separator text. Removal deletes the selected syntax and one
  necessary comma. Comments outside the removed node remain, even when that
  leaves a standalone comment. Comments **inside a removed/replaced container**
  are part of that container and are removed. No heuristic claims ownership of
  an adjacent comment. Whole-document formatting is a separate operation.
- Existing surrounding layout stays untouched. Newly inserted text follows
  `FormatOptions` and the destination's local indentation. Set `eol="\r\n"`
  explicitly when inserting into a CRLF document to avoid mixed newlines.
  `final_newline` only governs explicit formatting; localized modifications do
  not append a final newline to the whole source.

`apply_edits` uses coordinates in the original source, sorts a copy, and applies
validated nonoverlapping edits. Out-of-range spans, overlapping edits, multiple
inserts at the same offset, and boundaries inside a UTF-16 surrogate pair are
rejected. It is a general text primitive and does not itself validate JSON.

## Transactions

`transact` executes `Set`, `Remove`, `Insert`, and `Test` sequentially in memory.
Later operations see earlier results. Every operation/value is preflighted;
any failure returns only an error, with no partial result or filesystem writes.
`expected_source` provides an optional exact source-snapshot precondition.

`Test` ignores object member order and compares decoded strings; array order
matters. Numbers compare exact JSON lexemes: `1`, `1.0`, and `1e0` are distinct.
This is a deliberate lossless guard, not RFC 6902 numeric equality.
`Transaction.applied` counts successful operations including tests and no-ops.
The final edit array contains at most one contiguous replacement after removing
common prefix/suffix. It applies directly to the original source and is not
claimed to be the globally smallest set of disjoint edits.

## Formatting and stripping

Formatting modifies whitespace gaps, preserving every other token's raw text,
order, strings, number spelling and comment contents. Options are indentation
width 0..16 or tabs, LF/CRLF/CR, and optional final newline. Invalid, duplicate-key,
empty and comment-only documents are refused. Formatting is idempotent.

A range is validated in UTF-16, expanded to complete source lines, then only
minimal whitespace edits wholly contained in that expanded interval are kept.
Cross-boundary whitespace edits are omitted, so range formatting may retain
layout at its edges. Tokens outside the interval remain unchanged.

`strip_comments` uses token spans rather than regular expressions. By default,
comment code units become spaces while CR/LF and source length remain intact.
With `replace_with_spaces=false`, entire comment tokens are removed, including
line breaks inside block comments. It is lexical stripping, not JSON conversion:
it leaves trailing commas and existing syntax errors alone.

## Bounds and host behavior

Parser defaults: depth 128, at most 100 diagnostics. Configurable ranges are
depth 1..512 and diagnostics 1..1000; invalid options produce a diagnostic.
Parsing enforces a 100,000-value budget. These limits do not make tokenization
constant-memory; the library intentionally retains source and tokens.

The library bounds edit paths to 128 segments, transactions to 1,000 operations
and their supplied value texts to 8 Mi UTF-16 units in total.
The JSON host protocol accepts source up to 1 Mi UTF-16 units, requests up to
2 Mi units, request nesting up to 160, paths up to 128 segments, and batches up
to 128 operations. The library has additional transaction/path/value limits
documented in its public API. Applications should set their own input budgets.

The CLI previews to stdout by default. Explicit `--write` stages a same-directory
temporary file, syncs it, compares the current source and renames it. This is a
single-file replacement with a best-effort concurrent-change check; it is not a
cross-process lock, multi-file transaction, or power-loss durability guarantee.
Symbolic links are not writable targets. UTF-8 is the CLI's file encoding.
