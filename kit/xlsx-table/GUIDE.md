# Extract an XLSX range into a typed table

Use `@jsontable.extract_xlsx` to bring a deliberately selected worksheet rectangle
into the existing Table query, correction, lookup, summary and export pipeline.
This imports values into a new flat table. It does not edit the source workbook.

## Selection and command

The selection file requires exactly three fields:

```json
{"sheet":"Sales & Returns","range":"B3:G8","header":"first_row"}
```

Worksheet names are exact and case-sensitive. `range` is an uppercase A1 cell or
inclusive rectangle within A1:XFD1048576. No `$`, sheet-qualified address, named
range, whole-column range, automatic used-range guess or disjoint selection is
accepted. Duplicate matching sheet names fail. The first selected row supplies
unique nonempty text headers, with no trimming, case folding, coercion or rename.
A header-only selection produces an empty table. Alternatively supply names:

```json
{"sheet":"Sales & Returns","range":"B4:G5","header":["id","name","amount","active","serial","note"]}
```

Explicit names must match the width and be unique nonempty strings. In this mode
every selected row is data. Missing cells, fully blank rows and trailing empty
positions remain in place. Hidden or filtered rows are included.
Selection/query JSON uses the existing parser's last-value behavior for duplicate
object property names; use unique fields. Unknown or missing fields are rejected.

```sh
moon build cmd/xlsx-table cmd/preview --target js --frozen --strip -j 1 --target-dir /absolute/build
node /absolute/build/js/debug/build/cmd/xlsx-table/xlsx-table.js source.xlsx selection.json query.json json > /fresh/selected.json
node /absolute/build/js/debug/build/cmd/xlsx-table/xlsx-table.js source.xlsx selection.json query.json xlsx > /fresh/selected.xlsx
node /absolute/build/js/debug/build/cmd/preview/preview.js /fresh/selected.xlsx
```

Arguments: `SOURCE.xlsx SELECTION.json QUERY.json|- csv|json|xlsx|report`.
`-` in the query position means no table operation. Otherwise the existing
[version-1 query recipe](QUERY_TABLES.md) filters, sorts, projects and limits the
typed result. The sample query selects active rows, sorts numeric amount descending
and retains the identifier and evidence columns. Table operations are also
available to library callers without serializing through an intermediate format.

Every successful invocation writes a JSON diagnostic report to stderr. It has
the selection, header policy, input/matched/output row counts, output columns,
original worksheet row numbers in output order, and extraction warnings. The
`report` output mode writes the same report to stdout. Do not discard diagnostics
when displaying results. Row references describe this extraction; they are not a
digest or a durable reference after the source changes. Keep the original and its
hash alongside the selection and query. Separate export invocations read again.

All parsing, selection, query and serialization finish before dataset bytes are
written. Invalid input exits nonzero and writes no dataset bytes. The adapter
reads explicit regular files and writes stdout. Choose fresh output destinations:
shell redirection can truncate a source or an existing output before the program
starts. Host permissions, user confirmation, overwrite protection and readback
remain outside this adapter.

## Types and conservative refusals

- Inline/shared/string cells become Text. `001` and literal `=1+1` remain text;
  Boolean cells remain Boolean; absent positions remain Empty. Empty text and
  Empty are distinct. Rich text is flattened by the existing XLSX text reader.
- Numeric cells retain the exact raw token, accepted only when it is a finite
  JSON number without surrounding whitespace. No numeric-looking text coercion
  occurs. JSON export may normalize or round numerical representations.
- Dates and times remain raw numeric serials. No epoch conversion, number format,
  locale, style, display value or leading-zero number format is applied. A styled
  numeric identifier is still numeric, not its visually formatted representation.
  The report counts selected cells carrying style IDs; styles are not interpreted.
- Any selected formula, including an empty shared-formula follower, is refused.
  A formula's declared result range intersecting the selection is also refused,
  including an array/data-table anchor outside the selected rectangle. Caches
  are not accepted as fresh values. No recalculation occurs.
- Selected error and unknown cell types (including ISO date type `d`) fail.
  Any intersecting merged range fails, even when its anchor is outside. Duplicate
  selected coordinates and conflicting selected payloads fail rather than pick
  an arbitrary value. Headers are never silently invented.
- Worksheet coordinates, merge/formula range references, relationship identity
  and structural containers must be unambiguous. Malformed structure outside the
  selection can therefore refuse the import. Unselected scalar values and other
  worksheet contents are not imported or qualified. Other sheets may contain
  unsupported features. This is not whole-workbook semantic validation.

## Library

```mbt nocheck
let imported = @jsontable.extract_xlsx(
  opened_package,
  sheet_name="Sales & Returns",
  range="B3:G8",
  header=@jsontable.FirstRow,
)
let result = imported.table.query(recipe)
let original_rows = result.source_rows.map(i => imported.source_rows[i - 1])
let bytes = result.table.export_xlsx()
```

`XlsxTable` returns `table`, `sheet_name`, numeric `range`, `source_rows` and
`warnings`. Arrays belong to the new result; mutation cannot change the package.
`@xlsx.read_range` provides the lower-level dense rectangle, bounds and selected
styled-cell count. `extract_xlsx` accepts an already opened OPC package: callers
must apply the existing archive policy during open. No dependencies were added.

## Bounds and export limits

Import: at most 128 columns, 10,001 selected rows, 10,000 data rows and 100,000
selected positions including the first-row header. Headers plus data contain at
most 4,000,000 UTF-16 units. Library and CLI validate these before returning a
table. The CLI selection file is limited to 65,536 units; query limits are the
existing query contract. Each CLI input file is at most 8 MiB. CLI OPC open uses
8 MiB per compressed/uncompressed entry and 16 MiB total uncompressed content;
the existing CRC, path, entry count, compression ratio and XML limits also apply.
Files and XML are read in memory, not streamed; no production memory SLA is made.

CSV contains text values and loses types and Empty/empty-text distinctions. It
does not neutralize spreadsheet formula interpretation; open untrusted CSV as
text or use XLSX for literal formula-looking text. JSON omits Empty properties,
retains Boolean/text types and normalizes numbers; all-empty columns and an empty
table's schema need the report/original selection. JSON is not a lossless Table
codec. XLSX is a newly generated single sheet named `JSON data`, with explicit
typed values and no source styles, charts, links, formulas or unknown parts.
Its existing export limits are 100,000 cells including the generated header and
2,000,000 text units; a valid import may exceed an export's tighter limits and
fail serialization without output. Query projection/filtering can reduce it.

Tests cover synthetic packages, real CLI bytes, independent parser reopen and
typed XLSX reimport. They do not establish real-producer visual fidelity, Office
equivalence, workbook preservation, host save-conflict recovery, print readiness,
delivery or customer acceptance. Retain the original. No macros or formula code
are executed, but MoonLeaf is not a general hostile-document sandbox.
