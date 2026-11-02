# Provenance and third-party notices

MoonJSONC is an original, AI-assisted MoonBit implementation by YeeHh2004,
released under MIT. It is not a translation of Microsoft's source.

- Functional reference and test-only oracle:
  [Microsoft node-jsonc-parser](https://github.com/microsoft/node-jsonc-parser),
  MIT, npm version 3.3.1. Source and fixtures are not copied into this runtime.
  Functional coverage and deliberate differences are recorded in
  [COMPATIBILITY](docs/COMPATIBILITY.md).
- Runtime: MoonBit core, pinned with compiler 0.10.14+7d59c7ec9. Generated JS
  incorporates core code. Its complete distribution
  [LICENSE](licenses/MoonBit-core-LICENSE) and [NOTICE](licenses/NOTICE) are retained.
- Test tooling: Playwright 1.62.1, Apache-2.0. Node and npm dependencies are
  development-only and pinned in `package-lock.json`; they are not bundled into
  the Mooncakes archive or browser engine.
- Browser/release assets include this project's MIT license and the core
  license/notices. No external font, analytics service or UI framework is used.
- Ecosystem projects cited in `docs/SELECTION.md` are comparisons, not incorporated
  dependencies or endorsements.

If a competition requires application prose to be entrant-written, the separate
AI-assisted reference draft must be checked and rewritten by the entrant.
