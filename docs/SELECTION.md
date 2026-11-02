# Ecosystem scope and project rationale

Research date: **2026-11-02**. Checked the public Mooncakes module catalogue and
selected GitHub READMEs, public interfaces and source. Search cannot prove that
no unpublished or recently changed competitor exists; this document identifies
the concrete responsibilities compared.

MoonJSONC supplies a reusable **source-text editing layer**: a caller selects a
typed structural path, obtains reviewable UTF-16 text edits, retains unrelated
comments/layout/numeric spelling, and can validate a sequence before accepting
any result. Ordinary JSON value parsing and serialization alone do not preserve
those source properties.

| Existing work | Observed focus | MoonJSONC's distinct responsibility |
|---|---|---|
| [MoonBit core/json](https://github.com/moonbitlang/core/tree/main/json) | JSON values, parsing and serialization | JSONC syntax/trivia spans and localized source edits |
| [f4ah6o/yyjj.mbt](https://github.com/f4ah6o/yyjj.mbt) | JSONC/YAML conversion, comment preservation, accessible CST | Path-to-source-edit API, overlap validation and atomic operation batches; no YAML conversion |
| [rustin-beep/jsonmbt](https://github.com/rustin-beep/jsonmbt) | Typed `.json.mbt` sources generating deterministic JSON | Update an existing JSON/JSONC document in place while retaining its source layout |
| [moonbitstack/moonjson](https://github.com/moonbitstack/moonjson) | JSON/JSONC values, pointer operations and printing | Original-source coordinates, local patches and editor cursor integration |
| [Xu107-hhh/moonbit-jsonpatch](https://github.com/Xu107-hhh/moonbit-jsonpatch) | Structural JSON Patch/diff and merge operations | Text fidelity and comments; transactions are not claimed to implement RFC 6902 |
| [yufenfei111/toml-mbt](https://github.com/yufenfei111/toml-mbt) | TOML tooling, including source-preserving editing | Separate JSON/JSONC format; TOML is not included to inflate scope |

This work overlaps useful primitives such as parsing and tree navigation. The
claim is a distinct, integrated source-editing API and verified workflows,
not that MoonBit has no JSONC parser or no comment-preserving tooling.

## Three independent integration scenarios

1. **Build/configuration automation.** A package manager or migration tool changes
   selected commands/dependencies, creates missing parent sections and removes
   obsolete fields. Unrelated developer comments and large numeric IDs stay
   intact. `examples/basic` and the package preset exercise this workflow.
2. **Editor settings integration.** A settings UI maps a cursor to a structured
   path, displays diagnostics on incomplete documents, edits nested values and
   formats selected lines. `examples/editor` and the settings preset exercise it.
3. **Deployment/configuration review.** A script or AI-tool host checks a source
   snapshot and version, stages several changes, then previews one resulting
   patch. A failed precondition yields no partial result. `examples/transaction`
   and the deployment preset exercise it.

Each scenario uses the same MoonBit package. The browser and Node CLI are thin
demonstration hosts; the parser, formatter and editing algorithms are MoonBit.
