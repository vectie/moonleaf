# MoonLeaf

> **Library · conservative OOXML alpha.** Read the
> [product contract](docs/PRODUCT_CONTRACT.md) for the format matrix, bounded
> archive boundary, host boundary and release gates.

MoonLeaf is a pure MoonBit, cross-platform core for previewing and making
deliberately small edits to Office Open XML documents.

| Format | Viewer subset | Lightweight edit |
| --- | --- | --- |
| `.docx` | Paragraphs, headings, lists, tables, basic run styles | Exact text replacement inside `w:t` |
| `.xlsx` | Sheets, common cell values, formulas, styles, merged ranges | Set a cell to inline text |
| `.pptx` | Slide order and size, text, shapes, pictures, transforms | Exact text replacement inside `a:t` |

MoonLeaf is not an Office clone. It preserves unrecognized package parts and
defaults to save-as-copy workflows so unsupported features are not silently
discarded.

The same MoonBit source is intended to compile for native, JavaScript, Wasm,
and Wasm-GC targets. Renderers consume the neutral structures in
`vectie/moonleaf/scene`; UI frameworks such as Rabbita remain outside this
library.

## Architecture

- `xml`: namespace-tolerant XML DOM, parser, and serializer
- `opc`: ZIP/OPC access, relationships, path safety, and part preservation
- `scene`: neutral document structures for UI renderers
- `docx`, `xlsx`, `pptx`: format readers and conservative editors
- root package: filename-based viewer dispatch

## Public entry points

- `@moonleaf.open` detects the viewer from a filename
- `@moonleaf.open_with_policy(filename, bytes, policy)` applies explicit
  per-open ZIP/OPC limits; `open` uses conservative defaults
- `@moonleaf.open_session(filename, bytes)` opens a DOCX, XLSX, or PPTX editing
  session and renders its initial scene
- `@moonleaf.open_session_with_policy(filename, bytes, policy)` carries the
  selected policy through verified save/reopen
- `DocumentSession::capabilities()` reports whether the detected format supports
  scene rendering, save-as-copy, text replacement, or cell editing
- `DocumentSession::scene()` and `diagnostics()` return defensive copies:
  callers may mutate returned nested arrays without changing the session
- `VerifiedDocumentCopy::bytes()` likewise returns a defensive byte copy, and
  `session()` returns the verified reopened session
- `@opc.open` and `@opc.open_with_policy` preflight ZIP metadata, require
  per-entry CRC integrity, and decode the OOXML container; `@opc.save` encodes it
- `@docx.read`, `@xlsx.read`, and `@pptx.read` return neutral scene values
- `@docx.preview_document` returns ordered DOCX paragraph/table/section flow
  with resolved alignment, spacing, indentation, CJK fonts, run emphasis,
  table widths, and page geometry for higher-fidelity host previews
- `@docx.replace_text`, `@xlsx.set_cell_text`, and `@pptx.replace_text`
  return new packages and leave the input package unchanged

Successful changes increment `revision` and set `is_dirty()`; a semantic no-op
returns the same session with the existing revision and dirty state. In particular,
text replacement returns `self` when `find == replacement` after capability/format
validation and before low-level DOCX/PPTX editor dispatch, so entity-coded source
XML is not needlessly canonicalized. XLSX `replace_text` remains unsupported even
when `find == replacement`. Failed edits leave the original
session and its saved bytes unchanged. Dirty tracking is deliberately
conservative: it records successful session edits relative to the opened
baseline, not a byte-for-byte comparison with that baseline or an undo model.
An edit-away/edit-back sequence therefore remains dirty until save.

Replacement is format-specific. DOCX replaces substrings independently within
each `w:t` node, so a match never spans runs. PPTX replaces only an `a:t` whose
entire text payload exactly equals the find string. XLSX editing targets a
validated cell and writes inline text; formula cells and non-anchor cells in a
merged range are rejected.

`save_as_copy()` serializes, reopens, and renders the result before returning
it. Unknown OPC parts are intended to be preserved, but byte-identical ZIP
layout, signatures, macros, encryption, unsupported relationship semantics,
and application-specific metadata are not preservation guarantees. OPC
`Package` and `Part` values are public mutable data; no defensive-copy claim is
made for package parts, and sessions expose no package-part accessor.

## Security and release limits

Every public open now uses a MoonLeaf-owned `ArchivePolicy`. The default bounds
the compressed input, entry count, per-entry compressed and uncompressed size,
total uncompressed size, compression ratio, path depth, path length, and
duplicate/aliased paths. MoonLeaf inspects central-directory metadata before
extraction, extracts with CRC verification enabled, and compares actual entry
names and sizes with the inspected metadata before parsing OPC parts.

This closes the ZIP resource/integrity release blocker; it is not a blanket
claim that every malicious document is safe. Macros, digital signatures,
encryption, external relationships, embedded active content, and unsupported
semantic features remain outside the trust guarantee. See
[archive security](docs/ARCHIVE_SECURITY.md) and the
[preservation matrix](docs/PRESERVATION_MATRIX.md).

## Status

This repository is an early implementation. The initial compatibility target
is unencrypted OOXML without macros or digital signatures. Advanced layout,
formula recalculation, charts, transitions, and animation are intentionally
out of scope.

## Development

```bash
moon check --target all
moon test --target all
moon info
moon fmt
```

## License

Apache-2.0. See package-level provenance notes for behavioral references.

### Current verification checkpoint

The prior broad checkpoint passed 93/93 tests on each target. For the current
archive-policy slice, `moon check --target all --warn-list +73` reports zero
errors; 12 focused OPC tests plus one root-policy test pass on wasm, wasm-gc,
JavaScript, and native (52 focused executions); and `moon info`, formatting, and
diff checks pass. The broad format suite was intentionally not repeated for
this bounded change.
