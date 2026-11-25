# Changelog

## 0.1.1

- Define the standard JSON target as RFC 8259 and ECMA-404 second edition
  (December 2017), with explicit delivery scope, implementation policies,
  resource limits and reproducible input/output cases.
- Add `parse_json` and strict JSON CLI/transport commands. Keep duplicate names
  as valid syntax while preserving the existing editor's ambiguity checks.
- Reject malformed UTF-8 bytes in CLI inputs, retain the explicit BOM rejection
  policy, and add strict grammar, encoding and consumer regressions.
- Include a direct standards example in both-backend CI and update the
  November application reference draft.

## 0.1.0

- Source-positioned JSONC scanner, tolerant bounded parser and typed tree queries.
- Cursor paths and source-ordered visitors for editor integrations.
- Token-preserving full/range formatting and offset-preserving comment stripping.
- Validated UTF-16 patches, nested source updates, removal and array insertion.
- Snapshot/test-guarded in-memory transactions with no partial result on failure.
- Direct MoonBit examples, a preview-first CLI, browser workbench and independent
  consumer; JS/Wasm GC tests, reference comparisons and CI.
