# MoonLeaf

> **Library · conservative OOXML alpha.** Read the
> [product contract](docs/PRODUCT_CONTRACT.md) for the format matrix, bounded
> archive boundary, host boundary and release gates.

MoonLeaf is a pure MoonBit, cross-platform core for previewing PDF and Office
documents and making deliberately small OOXML edits.

| Format | Viewer subset | Lightweight edit |
| --- | --- | --- |
| `.docx` | Paragraphs, headings, lists, tables, basic run styles | Exact text replacement inside `w:t` |
| `.xlsx` | Sheets, common cell values, formulas, styles, merged ranges | Cell text, bounded row and column edits |
| `.csv`, `.tsv` | Bounded UTF-8 tables with quoted fields and line breaks | Parse and serialize tables |
| `.pptx` | Slide order and size, text, shapes, pictures, transforms | Exact text replacement inside `a:t` |
| `.pdf` | Bounded text extraction to page-oriented Markdown | None |

MoonLeaf is not an Office clone. It preserves unrecognized package parts and
defaults to save-as-copy workflows so unsupported features are not silently
discarded.

The OOXML and CSV packages compile for native, JavaScript, Wasm, and Wasm-GC.
PDF text extraction uses `moonbitlang/pdflite` and supports native, JavaScript,
and Wasm-GC. Renderers consume the neutral structures in
`vectie/moonleaf/scene`; UI frameworks such as Rabbita remain outside this
library.

## Architecture

- `xml`: namespace-tolerant XML DOM, parser, and serializer
- `opc`: ZIP/OPC access, relationships, path safety, and part preservation
- `scene`: neutral document structures for UI renderers
- `csv`: bounded delimited-table parsing and workbook projection
- `docx`, `xlsx`, `pptx`: format readers and conservative editors
- `pdf_text`: bounded text extraction through `moonbitlang/pdflite`
- root package: filename-based viewer dispatch

## Public entry points

- `@moonleaf.open` detects the viewer from a filename
- `@csv.parse(text, delimiter~)` and `Table::serialize()` handle CSV and TSV;
  `@moonleaf.open` projects them into the neutral workbook scene
- `@csv.Table::insert_columns(at, count)` and `delete_columns(at, count)`
  edit whole CSV/TSV columns while preserving ragged rows.
  `@xlsx.insert_sheet_columns(package, sheet, at, count)` and
  `delete_sheet_columns` shift cells in simple XLSX worksheets while preserving
  styles and unrelated OPC parts. Formula-bearing workbooks, defined names,
  column widths, merged ranges, tables, drawings and other anchored features
  are rejected until their references can be rewritten safely. The JS preview CLI
  accepts `insert-columns SOURCE DISPLAY_NAME OUTPUT` or `delete-columns ...`
  with `{"sheet":"工作表1","column":2,"count":1}` on stdin. It writes a
  verified copy and reports `moonleaf.insert-columns.v1` or
  `moonleaf.delete-columns.v1`, including `requested_columns`,
  `changed_columns`, `saved_copy`, and `source_unchanged`. Coordinates are
  1-based, with at most 100 columns per operation and a 256-column preview
  request bound. XLSX uses the named worksheet; CSV/TSV uses `工作表1`.
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
- `@docx.preview_document` preserves direct DOCX list numbering metadata
  (numbering ID, level, format, label template, and start/restart) alongside
  ordered rich paragraphs for browser renderers
- `@pdf_text.extract(bytes)` returns page-oriented PDF text for indexing;
  encrypted files, empty text, oversized input, and oversized output fail
- `TextDocument::plain_text()` extracts bounded visible DOCX text for indexing
- `@xlsx.create(rows, sheet_name~)` creates a bounded single-sheet workbook
  using MoonLeaf's MoonBit OPC writer; `@csv.Table::serialize_quoted()` writes
  quoted CSV fields for spreadsheet exports
- `@xlsx.sort_sheet_rows(package, sheet, column, descending, has_header)`
  moves complete worksheet rows into a new package while retaining cell and
  row formatting. It rejects formulas and row-anchored workbook features
  whose references cannot yet be updated safely. The preview CLI `sort`
  command applies the same stable numeric/text ordering to XLSX, CSV and TSV
  and writes a separate file.
- `@xlsx.copy_sheet_row_styles(package, sheet, source_row, destination_row)`
  copies existing XLSX row/cell style IDs to another existing row in the same
  sheet. The destination's values and formulas remain unchanged; styled source
  cells can create blank destination cells. The preview CLI accepts
  `copy-row-styles SOURCE DISPLAY_NAME OUTPUT` with JSON on stdin:
  `{"sheet":"研究证据","source_row":2,"destination_row":3}`. It saves and
  reopens a separate XLSX copy and reports `moonleaf.copy-row-styles.v1` with
  `changed_formats`. Both rows must already exist; use `insert-rows` first when
  the destination row is new. Style IDs refer to the same workbook's styles,
  so copying formats between workbooks is unsupported.
- `@csv.Table::set_cells_text(edits)` applies up to 1,000 unique, 1-based cell
  edits to one copied CSV/TSV table. The JS preview CLI accepts
  `paste-range SOURCE DISPLAY_NAME OUTPUT` with JSON on stdin:
  `{"sheet":"工作表1","start_row":2,"start_column":1,"rows":[["甲","乙"]]}`.
  It writes a new XLSX/CSV/TSV copy and reports
  `{"contract":"moonleaf.paste-range.v1","pasted_cells":2}`. XLSX targets
  existing non-formula cells; CSV/TSV may extend the table and guard text that
  could be treated as a spreadsheet formula. Ragged input rows leave omitted
  cells untouched, while empty strings clear addressed cells.
- `@xlsx.set_number_format_places_range` sets 0–6 displayed decimal places
  for Number, Percent or Currency on a bounded XLSX range. It preserves raw
  values, formulas and unrelated styles, reuses identical custom format IDs,
  and leaves the input package unchanged. The preview CLI's `format-number`
  JSON request accepts optional `decimal_places`; its receipt includes that
  field when requested. Spreadsheet preview adds `decimal_places_cells` as
  one-based `[row,column,places]` triples for recognized formats. Unknown
  custom formats have no precision entry. CSV and TSV have no style records.
- `moonleaf-preview export-sheet-csv SOURCE SOURCE.xlsx SHEET OUTPUT` exports
  one named XLSX worksheet to a separate UTF-8 BOM CSV. It preserves sparse
  row positions and numeric values; formula expressions become protected text
  instead of trusting possibly stale cached results. The CLI verifies the CSV
  can be reopened within the 2 MiB reader limit and reports
  `moonleaf.export-sheet-csv.v1` with row, column and formula counts.
- `@docx.preview_document` returns ordered DOCX paragraph/table/section flow
  with resolved alignment, spacing, indentation, CJK fonts, run emphasis,
  table widths, and page geometry for higher-fidelity host previews
- `moon run --target js cmd/preview -- preview-docx FILE.docx` emits a bounded
  `moonleaf.docx-preview.v1` JSON layout for hosts such as PaiWork. Optional
  style values are JSON scalars or `null`. Table rows include `height_twips`
  and `height_rule`; cells include `grid_span`, `vertical_merge`, width,
  four margins in twips, and vertical alignment. Hosts can render merged cells
  and their spacing without rereading OOXML. Source document text remains data,
  so the host must escape it before rendering HTML.
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

Replacement is format-specific. DOCX literal replacement can span adjacent
simple `w:r` text runs within a paragraph, but not structural boundaries.
PPTX replaces only an `a:t` whose
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

### 0.1.15 compiler compatibility

Numeric parsing uses the current `core/string` integer and double APIs instead
of the removed `core/strconv.from_str` function. Numbering defaults, invalid
cached page counts and numeric spreadsheet dates have regression coverage.
On MoonBit 0.1.20260904, strict checks pass for all targets and **111/111 tests
pass on each of native, JavaScript, Wasm and Wasm-GC**. No public API or document
fidelity claim is expanded by this compatibility patch.

### Current verification checkpoint

The prior broad checkpoint passed 93/93 tests on each target. For the current
archive-policy slice, `moon check --target all --warn-list +73` reports zero
errors; 12 focused OPC tests plus one root-policy test pass on wasm, wasm-gc,
JavaScript, and native (52 focused executions); and `moon info`, formatting, and
diff checks pass. The broad format suite was intentionally not repeated for
this bounded change.

## Import a DOCX business table

Use `cmd/docx-table` to discover and select a Word body table, apply an existing
Table query recipe, and create a fresh CSV, JSON or literal-text XLSX dataset.
The source digest, original row numbers and import limits accompany the output.
See [DOCX table import](docs/DOCX_TABLES.md) and `kit/docx-table` for the retained
supplier-comparison example. Merged or unsupported selected content is refused.

## Correct one presentation text run

Use `cmd/pptx-edit` to inspect source-bound slide/run targets and create a verified
fresh PPTX copy with only the chosen ordinary text run changed, including grouped
shapes. Repeated text elsewhere is preserved. See [targeted presentation
correction](docs/TARGETED_PPTX.md) and `kit/pptx-edit` for a real producer fixture.

## Compare an original workbook and a client copy

Use `cmd/xlsx-compare ORIGINAL.xlsx CLIENT_COPY.xlsx text` for a source-hashed,
read-only before/after report. Formula-expression changes and stored-cache changes
are separate, alongside typed cell values, sheet order/visibility and merges.
See [workbook comparison](docs/COMPARE_WORKBOOKS.md) and `kit/workbook-compare`.
This compares bounded supported content; it does not calculate formulas or claim
visual or whole-package equivalence when the report is empty.

## Correct workbook text in one verified copy

Use `cmd/xlsx-edit` to inspect existing text cells and apply an exact multi-sheet
JSON corrections recipe to a fresh verified XLSX copy. The report includes both
source digests and the supported before/after comparison. See [workbook text
correction](docs/CORRECT_WORKBOOK_TEXT.md) and `kit/xlsx-edit`. Formula cells,
merged cells and rich text are refused; formulas are never recalculated.

## Import a named Excel Table

Use `cmd/xlsx-named-table` to discover structured Excel Tables by name and export
their current data through the query pipeline. Headerless tables are supported,
totals are excluded, and the report retains original worksheet rows and source
hashes. See [named Excel Tables](docs/NAMED_XLSX_TABLES.md) and the retained
`kit/xlsx-named-table` example. Outputs are fresh extracted datasets.
