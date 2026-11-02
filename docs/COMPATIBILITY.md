# Functional scope and reference comparison

Reference: Microsoft's MIT-licensed
[node-jsonc-parser](https://github.com/microsoft/node-jsonc-parser).
The independent test oracle is pinned to npm `jsonc-parser@3.3.1` in the lockfile.
MoonJSONC is an independent, AI-assisted MoonBit implementation. No Microsoft
source or fixture files are copied into the runtime. It is not a drop-in port
and does not claim complete JavaScript API or byte-for-byte output compatibility.

| Reference functionality | MoonJSONC public API | Contract |
|---|---|---|
| Scanner | `scan` | Source spans, trivia mode, decoded strings, lexical errors; returns an array rather than a mutable scanner cursor |
| Tolerant parse / parseTree | `parse`, `node_value` | Partial trees, options, diagnostics and original source |
| Visitor | `visit` | Source-ordered events; callback can stop all delivery; no subtree-pruning callback contract |
| Location and tree lookup | `get_location`, `find_node`, `node_at_offset`, `to_pointer` | Typed key/index paths and UTF-16 positions |
| Comment removal | `strip_comments` | Exact token spans; optional length-preserving replacement |
| Format | `format` | Whitespace edits, tabs/spaces/EOL/final newline; conservative line-expanded range mode |
| Modify | `modify`, `insert` | Create/replace/remove paths and insert array entries, preserving unrelated source |
| Apply edits | `apply_edits` | Range, overlap and surrogate-boundary validation |
| Coherent multi-step changes | `transact` | Snapshot check, lossless test guards, all-or-error result, original-source patch |

Important deliberate differences:

- Defaults allow trailing commas. Use explicit parse options when comparing
  strict JSON or the reference parser's defaults.
- Duplicate keys are diagnosed and cannot be edited ambiguously.
- Formatting refuses erroneous documents; tolerant inspection still works.
- Formatting and insertion layout follows this library's contract, not the
  reference's exact whitespace/edit partition strategy. There is no custom
  object insertion-order callback; new properties append in deterministic order.
- `modify` takes strict JSON **source** for new values. A missing parent may be
  created, but scalar ancestors are not overwritten and sparse arrays are refused.
- Visitor error callbacks and wildcard `Location.matches` are not implemented;
  callers consume `Document.diagnostics` and typed paths directly.
- Transactions are an additional MoonJSONC API with exact numeric-lexeme tests.
- In the 3.3.1 reference, a comment token's reported value can incorrectly
  include preceding text (`1/*a*/`), which also affects length-preserving
  `stripComments`. MoonJSONC uses the actual token offset/length.
- The reference can report an array value as a property key after an empty
  object (`[{},"x"]`). MoonJSONC uses its structural context instead. Regression
  tests explicitly record these differences; they are not excluded silently.

`tests/differential.test.mjs` uses a fixed random seed and independent generated
fixtures. It checks token spans, decoded values, syntax/semantic reconstruction,
formatting invariants and idempotence, stripping, visitor events, and
set/remove/insert results. It also exercises malformed input. This is evidence
for the covered behavior, not proof of equivalence for every possible input.
