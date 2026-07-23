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
- `@opc.open` and `@opc.save` decode and encode the OOXML container
- `@docx.read`, `@xlsx.read`, and `@pptx.read` return neutral scene values
- `@docx.replace_text`, `@xlsx.set_cell_text`, and `@pptx.replace_text`
  return new packages and leave the input package unchanged

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
