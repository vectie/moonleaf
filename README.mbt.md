# MoonLeaf

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
- `@moonleaf.open_session(filename, bytes)` opens a DOCX, XLSX, or PPTX editing
  session and renders its initial scene
- `DocumentSession::capabilities()` reports whether the detected format supports
  scene rendering, save-as-copy, text replacement, or cell editing
- `DocumentSession::scene()` and `diagnostics()` return defensive copies:
  callers may mutate returned nested arrays without changing the session
- `VerifiedDocumentCopy::bytes()` likewise returns a defensive byte copy, and
  `session()` returns the verified reopened session
- `@opc.open` and `@opc.save` decode and encode the OOXML container
- `@docx.read`, `@xlsx.read`, and `@pptx.read` return neutral scene values
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

Archive policy remains a release blocker, but the ZIP decoder is not unlimited.
The vendored `hustcer/fzip` 0.8.5 uses fixed coarse defaults: maximum input
1 GiB, total and per-entry output 100 MiB, 100,000 entries, and deflate ratio
1000, plus filename/extra-field and central-directory validation. `unzip_sync`
checks central-directory sizes before entry allocation. CRC verification exists
but is disabled by default. MoonLeaf still needs configurable, stricter
per-open limits and an enabled, verified CRC/integrity policy before hostile or
untrusted archives are supported.

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

Independent gates pass 93/93 tests on wasm, wasm-gc, JavaScript, and native (372 executions), with 122 warnings, 0 errors, and a clean diff check. A regression covers a DOCX `w:t` edit inside a viewer-ignored top-level `w:sdt`: package-difference commit detection preserves the hidden edit, while XLSX exact existing Text-cell prechecks preserve semantic no-ops. A focused PPTX regression proves that identical replacement of entity-coded `A&#66;` with rendered `AB` is an exact-byte no-op, alongside the DOCX and XLSX no-op coverage.
