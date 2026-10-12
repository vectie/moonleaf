# Import an Excel Table by name

Excel workbooks often already contain named, structured Tables such as `Orders`.
MoonLeaf can now discover those definitions and import their current data rows
without a manually copied A1 rectangle. The existing query pipeline can filter,
sort and project the imported values into a fresh CSV, JSON or simple XLSX file.
The original workbook is retained unchanged.

## Discover, select and export

Build `cmd/xlsx-named-table` for JavaScript with your pinned dependencies and an
absolute external build directory:

```sh
moon --target-dir /absolute/external-build build cmd/xlsx-named-table --target js --frozen --strip -j 1
node /absolute/external-build/js/debug/build/cmd/xlsx-named-table/xlsx-named-table.js inspect source.xlsx
node /absolute/external-build/js/debug/build/cmd/xlsx-named-table/xlsx-named-table.js export source.xlsx Orders query.json json /absolute/fresh/orders.json
```

Syntax:

- `inspect SOURCE.xlsx` lists names, worksheet names, definition part paths,
  full and import ranges, column names, header/totals counts, data-row counts
  and whether calculated-column metadata is present.
- `export SOURCE.xlsx TABLE QUERY.json|- csv|json|xlsx FRESH_OUTPUT` selects an
  exact, case-sensitive Excel Table `displayName`. `-` skips the query. A query
  uses the existing [version-1 table recipe](QUERY_TABLES.md).

No named ranges, automatic used-range inference, sheet-name substitution,
substring matching or case folding occur. Tables are discovered only through
worksheet `tableParts` and internal exact-type relationships, in workbook sheet
and table-reference order. Unreferenced package parts are not treated as tables.
Both transitional and strict OOXML table relationship types are recognized.
Recognized internal chartsheets in the workbook sheet list are skipped; their
chart content is not inspected or imported.
Discovery reads definitions, not data cells; it does not guarantee export will
succeed. A workbook without Excel Tables returns an empty list.

The retained `kit/xlsx-named-table/orders.xlsx` has synthetic business data,
produced by XlsxWriter 3.2.9. Its Orders Table starts at B3 on `Sales Q4`, has a
formula-based totals row, and contains a hidden data row. The example query keeps
active orders and sorts by amount. It returns IDs `003`, `001` from original
worksheet rows 6 and 4. The totals row is excluded. Other examples include a
second worksheet Table and a headerless Table on a hidden sheet.
`orders-with-chartsheet.xlsx` is an openpyxl 3.1.5-saved variant with an unrelated
Cost chart chartsheet; it produces the same selected Table dataset.

## Selection and value semantics

- The full table `ref` is authoritative for the current snapshot. A changed
  definition is resolved afresh on the next invocation. It is not bound to an
  earlier inspection: compare the reported source SHA-256 when reviewing runs.
- Zero or one header row and zero or one totals row are supported. Absent
  `headerRowCount` defaults to one; absent `totalsRowCount` defaults to zero.
  `totalsRowShown` is not used to guess a physical totals row.
- Column order/names come from `tableColumns`. With a header row, the actual
  worksheet header cells must be the same unique nonempty text names in order.
  With no header, metadata supplies the names and every non-totals row is data.
- Totals rows are excluded before value reading, so their formulas do not block
  importing ordinary data. A table containing only headers or only one totals
  row produces an empty table with its columns retained in memory/CSV/XLSX.
- Hidden sheets and hidden/filtered rows are included. Table filters, saved sort
  state, styles, number formats and refresh connections are not applied.
- Selected data formulas, calculated-column metadata, errors, unsupported cell
  types and intersecting merged/formula-result ranges are refused. Formula
  caches are never accepted as fresh calculations. Local worksheet Tables only;
  query/XML table types and explicit external connection IDs are refused.
- Ordinary text, finite numeric tokens, Boolean values and missing cells use
  the existing [range-import semantics](XLSX_TABLES.md). Dates remain numeric
  serials, rich text is flattened, and leading-zero/formula-looking text stays
  text. This is value extraction, without calculation or workbook rewriting.

Missing parts, repeated references, ambiguous exact table/worksheet names,
missing/external/wrong-type table relationships, invalid ranges, inconsistent
counts, repeated column IDs/names and header disagreement fail rather than
choosing a guessed rectangle. Malformed definitions elsewhere in the workbook
may refuse discovery/import. This is bounded table discovery, not complete OOXML
validation or a general hostile-document sandbox.

## Library API

```mbt nocheck
let definitions = @xlsx.named_tables(package)
let imported = @jsontable.extract_xlsx_named_table(package, table_name="Orders")
let result = imported.table.query(recipe)
let original_rows = result.source_rows.map(i => imported.source_rows[i - 1])
let copy_bytes = result.table.export_xlsx()
```

`NamedXlsxTable` returns the ordinary `Table`, its resolved `NamedTable`
definition, original worksheet row numbers, and warnings. `NamedTable` includes
its source worksheet and exact part path, full reference, optional import
reference, columns and row counts. The import reference includes a header when
present and excludes totals; it is absent for a headerless totals-only table.
These APIs consume an already opened OPC package. The caller owns archive policy
and all file effects. No input package mutation occurs.

## Output and evidence

On success, the CLI prints one JSON report on stdout with source and output
SHA-256 values, query SHA-256 (or null), definition, input/matched/output counts,
selected column names, original worksheet rows in output order, warnings and
`readback_equal: true`. It prints errors on stderr and exits nonzero. Retain the
report with the dataset and original source. Hashes identify observed bytes;
they do not establish business truth or completeness of an upstream export.

All selection, query and serialization finish before writing. The destination
must be fresh: exclusive creation refuses an existing file, directory, symlink,
hardlink or the source itself. The new file is mode 0600 and its readback must
match serialized bytes before success. A write/readback failure can leave an
unverified file; it is retained, and retry requires another fresh destination.
Readback equality is not an Office visual-fidelity or client-delivery claim.

CSV loses types/empty-cell distinctions and keeps formula-looking text without
neutralization; spreadsheet applications may interpret it. Prefer typed XLSX
when preserving literal text matters. JSON omits missing fields and may normalize
numbers; an empty array cannot retain column schema. XLSX is a new plain single
sheet, without source Table definitions, formulas, styles or unrelated parts.
An extracted dataset is not a preserved client-copy workbook.

## Bounds and verification scope

At most 256 table definitions, 128 columns per table, 10,000 data rows and 100,000
selected positions excluding totals are supported. Column names and table names
are at most 255 UTF-16 units. The existing 4,000,000 text-unit range-import bound
and tighter query/export bounds apply; a valid import can still fail export.
These are in-memory operations, not a streaming/performance SLA.

The CLI reads regular files only, at most 8 MiB for a workbook and 65,536 bytes
for a UTF-8 query. Its archive policy allows at most 8 MiB per entry and 16 MiB
total uncompressed content, alongside existing CRC/path/resource policies.
No providers, external relationships, macros or live refresh are executed.

Focused MoonBit tests exercise definition resolution, data selection, totals,
headerless/empty cases, immutable source and meaningful refusals. Actual Node
commands verify query outputs, source-row provenance, typed XLSX literals and
fresh destinations. Python csv/JSON/XML and openpyxl independently read output
values and definitions. No native Office UI, graphical fidelity, host integration,
print readiness, delivery or customer acceptance is claimed.
