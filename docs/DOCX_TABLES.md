# Bring a Word business table into the analysis pipeline

Select one ordinary DOCX body table, keep its exact text and row references, then
filter, sort and export the result as CSV, JSON or a new XLSX. This is a table
import: the original Word file is never edited. It fills the gap between DOCX
preview/text correction and the existing `Table` analysis operations.

## Discover, choose and export

Build the JavaScript adapter with the pinned dependency graph and an absolute
external build directory:

```sh
moon --target-dir /absolute/external-build build cmd/docx-table --target js --frozen --strip -j 1
node /absolute/external-build/js/debug/build/cmd/docx-table/docx-table.js inspect kit/docx-table/suppliers.docx
node /absolute/external-build/js/debug/build/cmd/docx-table/docx-table.js export kit/docx-table/suppliers.docx kit/docx-table/selection.json kit/docx-table/query.json xlsx /fresh/suppliers.xlsx
```

`inspect SOURCE.docx` returns `moonleaf.docx-tables.v1`, the exact source SHA-256,
and direct body tables in document order. Each candidate has `id`, `rows`,
`columns`, `first_row` and `refusal`. A refused table has `columns: 0` and no
first-row text; the reason explains its unsupported content. A merged cover
table does not stop a later ordinary table from being imported. Malformed XML,
a rebound `w` prefix or document-wide complex fields can block all discovery.
Only direct `w:body/w:tbl` tables are candidates. Wrapped/nested tables, headers
and footers are not discovered. Discovery is not a complete document inventory.

The sample's `body/table:2` has supplier names, exact identifiers, amounts and
multiline notes. Its reusable query selects amounts at least 1000, sorts them
numerically descending and exports two suppliers, retaining original table rows
4 and 2. The merged cover table is explicitly refused.

Selection JSON requires exactly these four fields:

```json
{
  "version": 1,
  "source_sha256": "64-character SHA-256 returned by inspect",
  "table": "body/table:2",
  "header": "first_row"
}
```

IDs are one-based ordinals among direct main-body tables. They are meaningful
only with the exact source SHA-256, which export checks. Reinspect after the
source changes. `first_row` uses the first row as exact, unique, nonempty headers.
Alternatively use `"header": ["id", "supplier", "amount", "notes"]` to supply
exact column names and retain every row as data. Explicit header count must
match the table width. Headers are never trimmed, renamed or deduplicated.
Whitespace-only names are nonempty; choose useful names deliberately. A header-
only table is a valid zero-data-row import. Duplicate JSON properties use the
existing JSON parser's final value; provide unique property names.

`export SOURCE.docx SELECTION.json QUERY.json|- csv|json|xlsx FRESH_OUTPUT` applies
an optional existing [version-1 Table query recipe](QUERY_TABLES.md). `-` means
no query. Comparison mode is explicit: number mode may compare decimal text
numerically without changing its original spelling or literal text type.
The JSON stdout report includes source/output SHA-256, full selection and query,
counts, output columns, original one-based table row numbers in output order,
readback equality and warnings. Retain this report with the source and output.
A digest identifies bytes; it does not establish authorship or factual truth.

All input validation, extraction, query and serialization complete before an
exclusive `wx` file create. Existing files, source paths, hardlinks, symlinks and
directories are refused. The output is mode 0600 and its bytes are read back and
compared before success. Errors exit nonzero and emit no success report. A failed
write/readback can leave a partial or unverified fresh output; it is not deleted
or overwritten. Inspect the error and retry at a fresh destination. The adapter
reads a source snapshot without locking against concurrent changes; its digest
identifies that read snapshot. Hosts retain file permissions, source retention,
conflict handling and any sharing/delivery decisions. This is not a DOCX edited-
copy/save-as-copy workflow or render-evidence qualification.

## Text subset

- Standard transitional `w:document`, standard `xmlns:w`, exactly one direct body.
- Rectangular, unmerged direct-body tables with ordinary rows, cells, paragraphs
  and runs. An optional table grid must match the physical cell count.
- Adjacent `w:t` runs concatenate; rich-run formatting is not applied. All cell
  values remain literal text, including `001`, `12.50`, `true`, `=1+1` and empty
  strings. There is no number/date/Boolean/formula inference.
- Paragraphs join with one newline, preserving empty paragraphs. Tabs, `w:cr`
  and text-wrapping breaks become tab/newline characters. Nonbreaking and soft
  hyphens retain their Unicode characters. Text whitespace is not trimmed.
- Table/row/cell/paragraph/run properties are not rendered. Styles, list labels,
  inherited hidden-state, layout, page position and application display rules
  are not interpreted; extraction is source text, not a Word-visible-text claim.
  Ordinary bookmark/proofing markers are ignored, not exported as data.
- Selected merges/spans (including explicit span 1), skipped grid positions,
  direct hidden-run properties and tracked property changes are refused.
  Hyperlinks, content controls, tracked-change wrappers, simple fields, drawings,
  nested tables, page/column breaks and other unrecognized selected content are
  refused rather than silently flattened or dropped. Complex-field tokens
  anywhere in the main document refuse the workflow because their scope can
  cross table boundaries. Unselected tables are not semantically qualified.
- This is bounded extraction, not general namespace/OOXML validation, macro
  analysis, signature validation, hostile-document containment or Office fidelity.
  External resources are not fetched and no formulas/macros are executed.

## Outputs and library

CSV is fully quoted but spreadsheet applications may interpret formula-looking
text. Use XLSX when literal text cell typing matters. JSON retains every imported
string, including empty strings; a zero-row JSON array loses column schema, which
remains in the report. XLSX is a new simple sheet called `JSON data`, with explicit
inline-string cells. Source formatting, package parts, links and other tables
are not copied. It is a derived dataset, not a preserved Word file.

```mbt nocheck
let candidates = @jsontable.list_docx_tables(policy_opened_package)
let imported = @jsontable.extract_docx(
  policy_opened_package,
  table_id="body/table:2",
  header=@jsontable.FirstTableRow,
)
let result = imported.table.query(recipe)
let original_rows = result.source_rows.map(i => imported.source_rows[i - 1])
let xlsx = result.table.export_xlsx()
```

Library callers apply the OPC archive policy when opening and bind table IDs to
their source identity. Results own their arrays; mutating them cannot change the
source package. Existing DOCX editors, sessions and XLSX import APIs are unchanged.

## Bounds and verification

At most 1000 discovered direct-body tables; per selected table at most 10001
physical rows, 128 columns, 100000 physical cells and 4000000 UTF-16 text units.
An imported table has at most 10000 data rows and 4000000 header/data units.
The CLI source is a regular file of at most 8 MiB; selection and query files are
at most 64 KiB each. Archive limits are 8 MiB per compressed/uncompressed entry
and 16 MiB total uncompressed content, with existing CRC, path, ratio, entry and
XML bounds. Upstream parser bounds can refuse inputs before table ceilings.
Everything is in memory; no streaming/performance SLA is claimed. Existing XLSX
export ceilings (100000 cells including generated header, 2000000 text units)
may reject a larger valid import. Query projection/filtering can reduce it.

`jsontable/docx_test.mbt` tests the focused API on JS/native. The executable
`tests/docx_table_cli.py /absolute/build /fresh/evidence` uses a retained fixture
from python-docx 1.2.0 and standard-library independent DOCX/XLSX ZIP/XML and CSV
parsers to check actual exports, row mapping, digests, literal XLSX cells,
refusals and failed-write retry. Its producer script is retained but is not a
runtime/test dependency. These checks do not establish Microsoft Word visual
acceptance, full Office fidelity, MoonDesk UI integration, print readiness,
customer acceptance or broader historical runtime qualification.
