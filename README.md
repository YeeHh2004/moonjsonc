# MoonJSONC

[![CI](https://github.com/YeeHh2004/moonjsonc/actions/workflows/ci.yml/badge.svg)](https://github.com/YeeHh2004/moonjsonc/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

**MoonBit JSON/JSONC source editing for configuration tools, editors and automation.**

按结构化路径修改配置，保留无关注释、排版与数字原文；提供容错语法树、光标定位、
格式化补丁，以及带前置检查的批量事务。核心解析与编辑算法全部使用 MoonBit，
可用于 JavaScript 和 Wasm GC，不依赖浏览器、Node.js 或远程服务。

[在线工作台](https://YeeHh2004.github.io/moonjsonc/) ·
[Mooncakes](https://mooncakes.io/docs/YeeHh2004/moonjsonc) ·
[行为契约](docs/BEHAVIOR.md) · [功能对照](docs/COMPATIBILITY.md) ·
[选题与生态差异](docs/SELECTION.md)

## Why source editing?

A configuration updater should be able to change a command without deleting
the maintainer's explanation, reformatting unrelated fields or rounding a large
numeric identifier. MoonJSONC returns localized, reviewable text edits:

```jsonc
{
  // Keep the team convention documented.
  "scripts": {"test": "moon test"},
  "buildId": 9007199254740993
}
```

Set `["scripts", "test"]` to `"moon test --target wasm-gc"`; the comment,
unrelated whitespace and `9007199254740993` remain exactly as written.

## Install and use from MoonBit

Tested/pinned toolchain: **moonc 0.10.14+7d59c7ec9**, with matching core.

```sh
moon add YeeHh2004/moonjsonc@0.1.0
```

Add the import to your package's `moon.pkg`:

```moonbit
import {
  "YeeHh2004/moonjsonc" @jsonc,
}
```

```moonbit
fn main {
  let source = "{/* keep */\"enabled\":false,\"id\":9007199254740993}"
  let edits = @jsonc.modify(source, [Key("enabled")], Some("true")).unwrap()
  println(@jsonc.apply_edits(source, edits).unwrap())
}
```

Output:

```jsonc
{/* keep */"enabled":true,"id":9007199254740993}
```

The example uses `unwrap` for brevity. Applications should handle `Result` errors
and display diagnostics; errors never include a partially committed transaction.
`examples/consumer` is an independent, executable installation example.

## Public capabilities

| Area | APIs | Useful for |
|---|---|---|
| Syntax | `scan`, `parse`, `node_value` | Tokens, JSONC options, tolerant trees, bounded diagnostics |
| Navigation | `find_node`, `node_at_offset`, `get_location`, `to_pointer`, `visit` | Editor settings, structured inspection, source events |
| Presentation | `format`, `strip_comments` | Document/range formatting, comment removal with offsets intact |
| Source updates | `modify`, `insert`, `apply_edits` | Create, replace, remove and insert without rewriting unrelated source |
| Coherent batches | `transact` | Snapshot checks, `Test` preconditions, all-or-error multi-step changes |

Paths use `Key(String)` and `Index(Int)`. Replacement values are strict JSON
source strings, so exact numeric spelling survives. All positions are UTF-16
code units on both backends. Editing refuses malformed or duplicate-key
documents; tolerant parsing remains available for editor diagnostics.

## Run the three integration examples

```sh
git clone https://github.com/YeeHh2004/moonjsonc.git
cd moonjsonc
moon run examples/basic --target js
moon run examples/editor --target wasm-gc
moon run examples/transaction --target js
```

1. **Project configuration upgrade:** change build/test commands while keeping
   developer comments and large identifiers.
2. **Editor settings:** connect cursors, paths, diagnostics and nested values;
   inspect incomplete input and format selected lines.
3. **Deployment updates:** check a version/snapshot, change several fields and
   preview a single patch; reject the entire result on a failed precondition.

## CLI and browser workbench

Node.js 22+ hosts the compiled engine. Algorithms execute in MoonBit-generated
JavaScript; Node supplies file I/O and the browser supplies the interface.

```sh
npm ci --ignore-scripts
npm run build
node cli/moonjsonc.mjs --help
node cli/moonjsonc.mjs check config.jsonc
node cli/moonjsonc.mjs set config.jsonc '["service","replicas"]' '4'
node cli/moonjsonc.mjs format config.jsonc --check
npm run serve
```

Commands above use shell quoting that works in Bash and PowerShell. Preview is
the default. Add `--write` explicitly to update a file, or `--json` to inspect
patches. A transaction reads an array of operations from a JSON file:

```json
[
  {"op":"test","path":["version"],"value":"3"},
  {"op":"set","path":["service","replicas"],"value":"4"},
  {"op":"insert","path":["service","regions"],"index":1,"value":"\"west\""},
  {"op":"set","path":["version"],"value":"4"}
]
```

```sh
node cli/moonjsonc.mjs transaction deployment.jsonc operations.json
```

The workbench is at `http://127.0.0.1:4173`. It includes all three presets,
editable source, patch/diagnostic inspection, explicit adoption and download.
It sends no source data to a server. [Transport documentation](docs/PROTOCOL.md)
describes embedding the same engine in another host.

## Verification and scope

CI checks formatting, both target builds and tests, generated public interfaces,
Node workflows, an independent MoonBit consumer, package contents and Chromium
interactions on Linux; compiler/build/host checks also run on Windows. Seeded
tests compare scanning, parsing, formatting, stripping and structural edits
against Microsoft's `jsonc-parser@3.3.1`, with deliberate differences recorded.

See [reproducible development commands](docs/DEVELOPMENT.md) and
[validation evidence](docs/VALIDATION.md). This project implements the main
functional areas of that reference, with its own typed API and explicit bounds;
it does not claim full drop-in compatibility. It is a source-editing library,
not JSON Schema validation, a JSON5 parser, a YAML converter or a filesystem
transaction manager.

## License and provenance

MIT. Original, **AI-assisted implementation**. Microsoft `node-jsonc-parser` is a
functional reference and test-only dependency, not embedded runtime code.
[NOTICE](NOTICE.md) records references, runtime licenses and generated-output
notices. [CONTRIBUTING](CONTRIBUTING.md) explains focused changes and verification.
