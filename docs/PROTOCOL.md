# JSON transport, version 1

`protocol.process(request_json) -> response_json` is the same MoonBit entry used
by the browser and Node CLI. It does not access files, environment variables,
network or a shared session. A request is a JSON object with required `op` and
`source` strings. Unknown operations and malformed schemas return `ok:false`.

```js
import {process as moonjsonc} from './web/moonjsonc.mjs';
const result = JSON.parse(moonjsonc(JSON.stringify({
  op: 'set', source: '{/* keep */"enabled":false}',
  path: ['enabled'], value: 'true'
})));
// {ok:true, source:'{/* keep */"enabled":true}', edits:[...], changed:true}
```

| op | Additional fields | Response payload |
|---|---|---|
| `parse`, `check` | optional `options` | `valid`, `diagnostics`, `tree` |
| `scan` | `ignoreTrivia?:boolean` | `tokens` |
| `find` | `path` | `node` or null, diagnostics |
| `locate` | `offset` | path, pointer, isPropertyKey, offset, line, column |
| `visit` | optional parse options | source-ordered events, count, diagnostics |
| `strip` | `replaceWithSpaces?:boolean` | source |
| `format` | `options?`, `range?:{offset,length}` | source, edits, changed |
| `set` | `path`, `value` (JSON source string) | source, edits, changed |
| `remove` | `path` | source, edits, changed |
| `insert` | array `path`, `index`, `value` | source, edits, changed |
| `apply` | `edits:[{offset,length,content}]` | source, edits, changed |
| `transaction` | `operations`, `expectedSource?` | source, edits, changed, applied |

Paths are arrays of string object keys and integer array indices. The default
path is the root `[]`. `value` must be a **string containing strict JSON**, not
a JSON value in the transport. A string replacement therefore needs quoted JSON
inside it, e.g. `value: JSON.stringify('west')`. This also lets callers send
`value:'9007199254740993'` without host numeric rounding.

Options: `allowComments`, `allowTrailingComma`, `allowEmpty`, `maxDepth`,
`maxErrors` for inspection; `indentSize`, `useTabs`, `eol`, `finalNewline` for
formatting/edit generation. Structural edits always validate source as JSONC
with duplicates refused; parse options cannot bypass editing validation.

An error returns `{ok:false, code, error, diagnostics}`. Successful parsing may
still return `valid:false` and a partial tree, because tolerance is intentional.
Mutation errors return no partial source. Read-only inspection diagnostics do
not automatically become transport failures.

Tree nodes contain `kind`, `offset`, `length`, `raw`, `value`, `children`.
Number-node `value` is the exact numeric lexeme string; scalar JSON arithmetic
should be performed explicitly by the host if desired. Spans and edits use
original-source UTF-16 code units, matching JavaScript `slice` positions.

The outer transport uses MoonBit core's strict JSON decoder. Isolated surrogate
escapes can be inspected by the MoonBit JSONC API, but an outer transport request
containing a lone surrogate string is rejected by that strict decoder. Valid
Unicode, emoji, and strings containing the literal escape sequence `\\uD800`
are handled consistently. See [behavior bounds](BEHAVIOR.md#bounds-and-host-behavior).
