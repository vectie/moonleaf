# Import a Markdown pipe table

Turn a comparison, inventory or task table in a Markdown document into an
independent CSV, JSON or XLSX dataset. List the tables first, select one by its
local ID, and use an optional existing [query recipe](QUERY_TABLES.md) to filter,
sort or project columns. The original document is read only.

## CLI journey

After building `cmd/markdown-tables` for JavaScript, run the generated Node CLI:

```sh
node markdown-tables.js list notes.md > table-list.json
node markdown-tables.js export notes.md table-1 SOURCE_SHA256 query.json xlsx comparison.xlsx
```

Replace `SOURCE_SHA256` with the exact `source_sha256` from the list report.
Export refuses a changed source before writing anything. Choose a fresh output
path. Use `-` instead of `query.json` for every data row, and `csv` or `json`
instead of `xlsx` for those formats. The command prints a JSON evidence report.

`kit/markdown-tables/vendors.md` has two tables and an ignored fenced example.
Its `query.json` selects shortlisted suppliers, orders by numeric monthly cost
without converting cell types, and exports only the desired columns. The output
contains vendor 003 followed by 001, with physical source lines 17 and 15.

The list report contains table IDs, header/separator lines, literal column names,
row counts and every data-row line. The export report retains source/query/output
SHA-256, exact query, table ID, header/separator lines, output columns, input and
matched/output counts, selected physical source lines, warnings and byte-readback
status. Lines are one-based in the exact original bytes, with LF or CRLF counted
as one line break. Table IDs are document-order positions, not persistent IDs.

All detected tables are validated before list/export succeeds, including tables
other than the selected one and rows excluded by a query. A malformed recognized
table reports its physical line and prevents a partial successful result. Fix a
separate source copy and list it again. Keep original source and reports yourself;
this CLI does not copy, overwrite or delete the input.

## Supported literal syntax

- Standalone pipe-separated tables with a header followed immediately by a
  delimiter row. Each delimiter cell contains at least three hyphens, optionally
  with one colon at either edge. Alignment is recognized but not exported.
- Every header and data line needs an unescaped pipe. A one-column table therefore
  needs an outer pipe. Leading/trailing pipes are optional and, when present,
  always treated as borders. Write `| a | |` for a two-column row with a blank
  final cell; ambiguous shortened rows are not padded or truncated.
- Spaces and tabs at cell edges are trimmed. `\|` becomes a literal pipe and
  `\\` becomes one backslash; other backslashes are retained. Escape parity
  matters: an escaped backslash followed by an unescaped pipe is a delimiter.
- All values are Text, including empty strings, `001`, `12.50`, `true`, `null` and
  `=formula-looking` strings. There is no type inference. Numeric query mode can
  compare numeric text explicitly, without changing its output type.
- Inline Markdown stays literal: backticks, links, emphasis, HTML and entities
  are not rendered or decoded. Unescaped pipes split cells even in backticks;
  use an escaped pipe inside code text. This is not a general Markdown renderer.
- Top-level backtick/tilde fences of length three or more are skipped. Closing
  fences must use the same marker, be at least as long and have only trailing
  whitespace. An unclosed fence skips the remaining lines. Four-space/tab
  indented lines are excluded. Up to three leading spaces are allowed.
- Blank/non-pipe/indented lines or a fence end a table. Headers must be unique
  and nonempty, and every data row must have exactly the header width. Header-only
  tables are valid; no tables yields an empty list, distinct from an empty table.
- UTF-8 CLI input, optional initial BOM, LF and CRLF are supported. NUL and embedded
  or repeated carriage returns are refused.

Blockquotes, list nesting, HTML block/comment visibility, multiline/spanned cells,
Setext headings and arbitrary Markdown dialect behavior are not interpreted.
Discovery follows the literal standalone line rules above, not a rendered DOM;
for example, matching pipe lines inside an HTML comment can be discovered.
Review listed source lines. Tables embedded in complex Markdown should first be
copied to a simple standalone source file rather than treated as rendered output.

## Limits and output

The library accepts at most 4,000,000 UTF-16 units and 100,000 physical lines;
64 detected tables, 128 columns per table, 10,000 data rows per table, 16,384
UTF-16 units per header/cell, and 100,000 total cells including all headers.
The CLI reads regular files up to 8 MiB and query files up to 64 KiB.
The existing query and XLSX writer impose their own bounds as well.

Outputs are created exclusively with mode 0600 and read back byte-for-byte.
An existing destination, including the source, fails without overwrite. A failed
write/readback is not a success: retain any resulting file and retry to a fresh
path. Readback verifies bytes, not rendered document fidelity.

CSV is text interchange; spreadsheet apps can interpret formula-looking strings
when opening it. XLSX uses literal inline-string cells, retaining leading zeros
and preventing formula inference by the exporter. JSON uses string values for
all cells; empty JSON arrays need the report's column schema. No macros, formulas,
links or active content are executed by the importer.

## Library

```mbt nocheck
let tables = @jsontable.parse_markdown_tables(markdown_text)
let selected = tables[0]
let result = selected.table.query(recipe)
let physical_lines = result.source_rows.map(i => selected.source_lines[i - 1])
let bytes = result.table.export_xlsx()
```

`MarkdownTable` exposes `id`, `header_line`, `separator_line`, `source_lines` and
`table`. `MarkdownTableError::InvalidMarkdownTable` carries a physical `line`
(or 0 for document-level limits) and a reason. These are ordinary mutable MoonBit
values; reparsing the source produces a fresh independent result.

This is a focused new intake adapter related to PRD W05. It does not provide a
MoonDesk UI, Markdown edit/writeback, DocumentSession render verification, source
completeness, factual verification, Office fidelity, customer acceptance or
permission to share. Synthetic offline fixtures establish the tested subset.
