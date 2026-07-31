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
returns a new package for every edit, making save-as-copy the natural workflow.
The same MoonBit source is tested on native, JavaScript, Wasm, and Wasm-GC.

## Architecture

- `xml`: namespace-tolerant XML DOM, parser, and serializer
- `opc`: ZIP/OPC package access, relationships, path safety, and preservation
- `scene`: neutral document structures for UI renderers
- `docx`, `xlsx`, `pptx`: format readers and conservative editors
- root package: filename-based viewer dispatch

UI frameworks and platform-specific file pickers remain outside this library.
MoonDesk or another client can render `scene` values through its own components.

## Safe open boundary

`@moonleaf.open` and `open_session` use a conservative MoonLeaf-owned archive
policy by default. Explicit `open_with_policy` and `open_session_with_policy`
variants let a host set stricter per-open limits. ZIP central-directory
metadata is bounded before extraction; extraction always verifies entry CRCs;
and extracted names and sizes must agree with the inspected metadata.

This protects the in-memory ZIP/OPC boundary, not all document semantics.
Macros, signatures, encryption, active content, and unsupported relationship
behavior are not safety or preservation guarantees. See
[archive security](docs/ARCHIVE_SECURITY.md) and the
[preservation matrix](docs/PRESERVATION_MATRIX.md).

## Scope

The initial compatibility target is unencrypted OOXML without macros or digital
signatures. Advanced layout, formula recalculation, charts, transitions,
animations, tracked changes, and pixel-perfect Office fidelity are intentionally
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
