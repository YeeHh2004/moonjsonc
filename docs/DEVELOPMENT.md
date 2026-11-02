# Reproducing the build

Use **MoonBit/compiler and core 0.10.14+7d59c7ec9**, Node.js 22 or later,
and Python 3 for the publish-archive audit. CI installs the exact compiler/core
with the pinned setup action. Install the same version via the
[MoonBit toolchain instructions](https://docs.moonbitlang.com/en/latest/toolchain/moon/commands.html).
`node scripts/build.mjs` rejects a different toolchain instead of silently
generating a mismatched browser bundle.

```sh
npm ci --ignore-scripts
moon version --all
moon fmt --check
moon check --target js --deny-warn
moon check --target wasm-gc --deny-warn
moon test --target js --deny-warn
moon test --target wasm-gc --deny-warn
moon build --target wasm-gc
moon info
git diff --exit-code -- '*.mbti'
node scripts/build.mjs
npm test
node scripts/check-consumer.mjs
python scripts/check-mooncake.py
npx playwright install chromium
node tests/browser.mjs
```

On a Linux machine without browser system libraries, use
`npx playwright install --with-deps chromium`. On Windows, local browser testing
can use an installed Edge with `BROWSER_CHANNEL=msedge` (set the environment
variable using the syntax of your shell). CI tests downloaded Chromium.

`check-consumer.mjs` builds an independent consuming module on JS and Wasm GC.
After publishing, `node scripts/check-consumer.mjs --registry` downloads the
public package and checks its source against this checkout before running it.

```sh
moon run examples/basic --target js
moon run examples/editor --target wasm-gc
moon run examples/transaction --target js
node scripts/serve.mjs
```

The server binds `127.0.0.1:4173`. The website uses the compiler-generated JS
engine. `web/build-info.json` records version, source commit, compiler and engine
SHA-256. Build after committing when preparing release provenance. Generated
files, dependencies and temporary outputs are ignored by Git.

## Source layout

- `scanner.mbt`, `parser.mbt`, `tree.mbt`: syntax and diagnostics.
- `location.mbt`, `visitor.mbt`: editor/navigation integration.
- `strip.mbt`, `format.mbt`: lexical cleanup and whitespace patches.
- `edits.mbt`, `modify.mbt`, `transaction.mbt`: validated structural changes.
- `protocol/`: bounded JSON transport, shared by hosts.
- `bridge/`, `cli/`, `web/`: exports, filesystem adapter and interactive demo.
- `examples/`: three direct consumers plus an independent installation example.
- `*_test.mbt`, `tests/`: backend tests, reference/model checks, CLI and browser.

Substantive changes belong in focused commits with regression evidence. CI
checks formatting, public interfaces, both targets, independent installation,
reference comparisons, CLI workflows and the browser. Package publication is
separate from CI and should follow a successful validation of the same revision.
