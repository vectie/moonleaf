# MoonLeaf

> **Library · conservative OOXML alpha.** Read the
> [product contract](docs/PRODUCT_CONTRACT.md) for the format matrix, bounded
> archive boundary, host boundary and release gates.

The [responsibility and testability map](docs/RESPONSIBILITY_AND_TESTABILITY.md)
separates archive, format, scene, host, and qualification responsibilities.

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
For higher-fidelity DOCX previews, `@docx.preview_document` retains ordered
paragraph/table/section flow and resolved layout metadata without introducing a
UI dependency.

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

## Reshape imported tables

[Pivot long observations](docs/PIVOT_TABLES.md) into a wide comparison using
explicit identifier, key and value columns, then export a fresh CSV, JSON or
XLSX copy. Duplicate cells are rejected unless an explicit first/last policy is
chosen. This complements [unpivot](docs/UNPIVOT_TABLES.md) and
[grouped summaries](docs/SUMMARY_TABLES.md).

## Import an explicit XLSX range

[Select a worksheet, rectangle and header policy](docs/XLSX_TABLES.md) to import
typed scalar values into the same Table pipeline, query them and export a new
CSV/JSON/XLSX table. Sparse positions and text identifiers are preserved;
selected formulas, errors and intersecting merges are refused. Dates remain raw
serials and the original workbook is never rewritten by extraction.

## Import CSV/TSV as explicitly typed data

[Apply a reusable column schema](docs/TYPED_DELIMITED.md) to preserve text IDs,
convert chosen amount/Boolean columns, name missing-value markers and rename or
select columns. Export a fresh JSON/CSV/XLSX dataset, or pass the typed Table to
existing queries and summaries. No values or types are guessed.

## Correct one DOCX text occurrence

[Inspect and select a supported text element](docs/TARGETED_DOCX.md), including
one repeated paragraph or table-cell value, and write a fresh reopened copy.
Other occurrences and package parts remain unchanged; the request is tied to the
inspected source digest and exact expected text.

### Presentation review outlines

`cmd/pptx-outline` exports ordered slide text, ordinary tables and linked speaker
notes as fresh JSON or Markdown, with the original digest and source references.
Hidden slides remain visible in the outline; unsupported content is disclosed.
See [the workflow and limits](docs/PRESENTATION_OUTLINE.md).

## Edit a scoped review sheet

[Export selected CSV/TSV columns for editing](docs/REVIEW_SHEETS.md), retain stable
row keys, and import changed cells into the existing typed correction recipe.
The Python host adapter creates a fresh full-table copy with original row order,
unselected columns and text-value readback evidence. Reordered review sheets are
supported; source changes, missing keys and existing destinations are refused.

## Carry review edits onto a newer export

[Compare original, reviewed and current values](docs/REBASE_REVIEW_EDITS.md),
resolve conflicting cells explicitly, and create an ordinary proposal bound to
the current CSV/TSV source. Unrelated current changes and added records survive;
already-applied edits need no second correction and deleted rows stay absent.

## Combine independent reviewed corrections

[Merge two frozen CSV/TSV proposals](docs/MERGE_REVIEW_EDITS.md) against one
retained source: keep disjoint changes, count shared agreement once and resolve
conflicting values explicitly before the existing verified-copy workflow.

## Review assigned records with context

[Export explicit record batches](docs/REVIEW_BATCHES.md) with immutable context
columns, collect only the assigned corrections, and continue through the existing
full-source proposal, merge, selection, rebase and verified-copy workflow.
