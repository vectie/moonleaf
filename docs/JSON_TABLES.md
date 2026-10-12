# JSON tables

`vectie/moonleaf/jsontable` opens a JSON array of objects with `parse(text)` or JSON Lines with `parse(text, jsonl=true)`. JSONL accepts blank lines and CRLF. Each nonblank line must be an object.

Columns are the union of top-level keys, in first-seen order. Missing fields are blank. JSON null is the text `null`. Strings remain strings, booleans and numbers retain their types for XLSX. Numeric spelling may be normalized by the JSON parser (12.50 becomes 12.5). Nested objects and arrays become compact JSON text.

- `table.columns`, `table.rows`: typed table data
- `table.text_rows()`: display values without the header
- `table.workbook()`: MoonLeaf workbook scene, including the header
- `table.export_csv()`: fully quoted CSV, with the header
- `table.export_xlsx()`: single-sheet XLSX bytes, with a styled header

The usual `@moonleaf.open(filename, bytes)` also recognizes `.json`, `.jsonl`, and `.ndjson`. This projection does not edit or write back to the JSON source. Existing XLSX writer limits apply (256 columns, 100000 cells, 2 MB cell text). CSV has no cell typing; use XLSX when typed numeric and boolean cells matter.

Validated on the pinned MoonBit toolchain: all 159 MoonLeaf Wasm tests pass, including JSON/JSONL workbook opening, Unicode, optional keys, numbers, booleans, nested values, and independent CSV/XLSX reopen. Product Wasm build passes.

For cross-file enrichment against a unique-key JSON/CSV/TSV reference, see [LOOKUP_TABLES.md](LOOKUP_TABLES.md). The new `parse_delimited` adapter and `Table::lookup` return a prepared table plus matched/unmatched input row identities for export.

For grouped counts, sums and means across imported/enriched tables, see
[SUMMARY_TABLES.md](SUMMARY_TABLES.md). `Table::summarize` produces a reusable table;
`Table::export_json` complements CSV/XLSX output. A compiled Node CLI accepts
CSV/TSV/JSON/JSONL on stdin and a reusable JSON summary specification.

For mapped supplier catalogs and order XML, see [XML_RECORDS.md](XML_RECORDS.md).
`parse_xml_records` produces the same Table with explicit namespace-aware fields;
its CLI exports CSV, XLSX or JSON. `export_json(omit_empty=true)` omits Empty
properties to keep missing values distinct from empty strings on JSON reimport
when the column appears elsewhere; the default null output is unchanged.

For wide exports with months or questions in separate columns, see
[UNPIVOT_TABLES.md](UNPIVOT_TABLES.md). `Table::unpivot` makes tidy name/value rows
with repeated identifiers for existing summaries, lookups and exports.

For literal pipe tables in Markdown notes or README exports, see
[MARKDOWN_TABLES.md](MARKDOWN_TABLES.md). Discovery lists physical source lines;
selected-table exports preserve these locators after query filtering and sorting.
