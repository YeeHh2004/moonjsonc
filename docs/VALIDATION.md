# Validation evidence

The reproducible commands are in [DEVELOPMENT](DEVELOPMENT.md). Current hosted
results are linked from [GitHub Actions](https://github.com/YeeHh2004/moonjsonc/actions).
Counts below describe test groups or generated cases, not a percentage claim
of full reference compatibility or a guarantee of contest acceptance.

| Check | Evidence |
|---|---|
| MoonBit core | 63 tests run independently on JS and Wasm GC with warnings denied; covers scanning, parsing, formatting, path lookup, edits and transactions |
| Coverage | MoonBit core report: 923/1025 measured points (90.05%) in the local verification; CI regenerates and uploads its report |
| Reference comparison | 360 seeded generated JSONC documents; scanner spans/values, tree values, formatting invariants/idempotence, stripping and visitors |
| Structural editing oracle | 1,080 generated set/remove/insert operations compared with Microsoft's jsonc-parser 3.3.1 |
| Invalid input | 180 generated damaged documents plus depth, diagnostic-budget, 20,000-error-token and 2,000-level nesting regressions |
| Exact source | Big integers, negative zero, large/small exponents, CRLF, comments, escaped/lone surrogates and UTF-16 range boundaries |
| Host behavior | 25 Node test groups including reference/adversarial cases; JSON request budgets, invalid schemas, stale snapshots, test failures, CLI preview/write/rollback and stdin |
| Adversarial edits | 67 fixed probes checked with both parsers and original-source patch replay, including comment-heavy deletion, empty containers and failed transactions |
| Browser | 14 desktop/mobile interaction checks: three presets, edits, adoption, failed transactions, download and no page errors |
| Independent consumer | A separate module imports the public package API and runs on JS/Wasm GC; `--registry` repeats against the published archive |
| Packaging | `scripts/check-mooncake.py` validates the generated ZIP, required sources/docs/licenses and exclusion of build outputs/dependencies/credentials |

The workbench and CLI use the same compiled MoonBit engine. CI builds it from
the checked-out revision. Pages deployment consumes the successful CI artifact
and rejects superseded builds, so a separate JavaScript mock cannot satisfy the
browser checks.

Differences from the test oracle are explicit in [COMPATIBILITY](COMPATIBILITY.md),
including numeric test semantics, range-formatting rules, duplicate keys and
two reference token/context quirks. Error recovery is useful but is not treated
as permission to edit invalid source.
