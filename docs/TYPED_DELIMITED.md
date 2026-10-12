# Import a delimited export with explicit column types

Use a schema to turn CSV or TSV exports into a new typed dataset. Keep customer
IDs such as `001` as text, convert chosen amounts to numbers, map explicit `YES`
and `NO` tokens to Booleans, name missing-value markers, and select/rename columns
in a chosen order. The resulting Table works with MoonLeaf's existing queries,
lookups, summaries and JSON/CSV/XLSX exports. Nothing is inferred from appearance.

This complements keyed cell corrections: one reusable schema applies to every
row, rather than requiring one before/after correction for each amount or flag.
It does not edit an existing workbook or evaluate spreadsheet formulas.

## Run the synthetic example

With the pinned toolchain and the unchanged module dependencies installed:

```
moon build cmd/typed-import cmd/query cmd/xlsx-table --target js --frozen --strip -j 1 --target-dir /absolute/external-build
node /absolute/external-build/js/debug/build/cmd/typed-import/typed-import.js csv kit/typed-import/source.csv kit/typed-import/schema.json json > /fresh/typed.json
node /absolute/external-build/js/debug/build/cmd/typed-import/typed-import.js tsv kit/typed-import/source.tsv kit/typed-import/schema.json xlsx > /fresh/typed.xlsx
node /absolute/external-build/js/debug/build/cmd/query/query.js json /fresh/typed.json kit/typed-import/query.json json > /fresh/active.json
node /absolute/external-build/js/debug/build/cmd/xlsx-table/xlsx-table.js /fresh/typed.xlsx kit/typed-import/selection.json - json
```

The example returns five typed rows. The existing Boolean/numeric query then
selects active IDs `001`, `005`, `1` in descending amount order. XLSX reopening
retains the zero-padded ID, numeric amount, Boolean flag and literal `=1+1` text.

Arguments: `csv|tsv SOURCE SCHEMA csv|json|xlsx`. Input paths must be explicit
regular UTF-8 files, not stdin. Successful output goes to stdout; conversion and
serialization finish before any dataset bytes are written. A refusal exits
nonzero with a diagnostic on stderr and no dataset stdout. Errors identify the
source column and one-based parsed data-row number, excluding the header; quoted
multiline records count once, so this is not a physical file-line number.

The CLI does not choose a destination or overwrite any input. Shell redirection
can truncate an existing file before the command starts: always choose a fresh
path distinct from the source/schema and check the exit code. The host still owns
file permissions, confirmations, source identity, conflict handling, save/readback
and any verified-copy label.

## Schema

```
{"version":1,"columns":[
  {"source":"Customer ID","name":"id","kind":{"type":"text"},"trim":false,"nulls":[]},
  {"source":"Gross amount","name":"amount","kind":{"type":"number"},"trim":true,"nulls":["","NULL"]},
  {"source":"Enabled","name":"active","kind":{"type":"boolean","true":"YES","false":"NO"},"trim":true,"nulls":["NULL"]}
]}
```

All fields are required and unknown fields are refused, including inside `kind`.
The existing JSON parser uses the last value of duplicate object keys; supply
unique keys. Version 1 is the only supported version.

- `source`: exact existing input header, including case and whitespace. All input
  headers must be nonempty and unique, and all rows rectangular, even if some
  columns are not selected.
- `name`: unique nonempty output header. Schema order controls output order.
  Unselected input columns are dropped. A source column may deliberately appear
  twice under different output names, for example raw text beside a typed amount.
- `trim`: when true, removes only ASCII space, tab, CR and LF at the two ends.
  It does not change internal whitespace, case, Unicode or locale. False preserves
  exact text and makes surrounding whitespace invalid for number conversion.
- `nulls`: at most 16 distinct exact string markers mapped to Empty, after the
  optional trim. No null marker is implicit. With `[]`, text `""`, `null`, `NULL`
  and whitespace remain literal text. With `["", "NULL"]`, those two exact
  strings become Empty. Missing-value markers must already be trimmed if trim
  is enabled. Empty and empty text remain different in the in-memory Table.
- `kind.type = text`: keeps the post-trim value as text. This is the correct
  choice for IDs, dates, currency-formatted text and arbitrary-precision numbers
  that should remain literal strings.
- `kind.type = number`: accepts finite JSON-number syntax, including negatives,
  decimals and exponents. `01`, `+1`, `1,000`, currency symbols, empty strings,
  `null`, Booleans, infinity and formula expressions fail unless the exact text
  is a configured null marker. The Table retains the accepted numeric spelling.
- `kind.type = boolean`: also requires nonempty distinct `true` and `false`
  strings. Matching is exact after optional trim; no extra spellings or case
  conversion are assumed. Tokens cannot overlap null markers and must already
  be trimmed when trim is enabled.

Any invalid selected value refuses the whole import, including one on the final
row. Unselected cells are parsed as ordinary text and are not type-checked. No
rows are silently dropped. Correct the input or schema and rerun; parsing a
schema once and using it repeatedly never mutates the schema or prior results.

## Library

```
let schema = @jsontable.parse_delimited_schema(schema_json)
let table = @jsontable.parse_typed_delimited(csv_text, schema)
let tsv_table = @jsontable.parse_typed_delimited(tsv_text, schema, delimiter='\t')
let selected = table.query(@jsontable.parse_query_recipe(query_json))
let workbook_bytes = selected.table.export_xlsx()
```

The return type is the existing `Table`. `TypedDelimitedError` distinguishes
schema errors, delimited-input/bound errors, and cell conversion errors with
source row/column. This creates a fresh table, without changing `parse_delimited`
and its established all-text behavior.

## Bounds and fidelity

- Existing CSV/TSV parser: at most 2,097,152 UTF-16 input units, 10,000 rows
  including header, 256 columns and 100,000 input cells. BOM, quoted delimiters,
  escaped quotes, embedded newlines and CRLF are supported.
- Schema: at most 65,536 UTF-16 units, 1–128 output columns, names and tokens at
  most 4,096 units. Output: at most 100,000 cells including header and 4,000,000
  UTF-16 units counting headers and scalar text. This limits repeated projection.
- CLI: each regular file at most 8 MiB. These are whole-file, in-memory operations;
  no streaming, database-scale or adversarial-memory performance claim is made.
- Numeric validation/export uses the existing double-precision JSON model, not
  decimal accounting or arbitrary precision. Large integers may round, extreme
  small magnitudes may underflow, and JSON export can normalize spelling. Store
  precision-sensitive identifiers/values as text; no currency/date interpretation
  or general formula recalculation occurs.
- JSON export omits Empty properties and can lose empty-table/all-empty-column
  schema on reimport. Empty text stays `""`; literal `null` text stays a string.
- CSV loses scalar types and collapses Empty with empty text. Quoting does not
  prevent spreadsheet applications from interpreting formula-like strings;
  choose typed XLSX or JSON for untrusted text.
- XLSX is a new flat single-sheet dataset, not a source-package round trip. It
  preserves supported scalar types; formula-looking text is inline text. CR and
  CRLF text are preserved using XML character references. XML 1.0-forbidden
  controls (including NUL), U+FFFE/U+FFFF and unpaired UTF-16 surrogates are
  refused during XLSX export, including in column names; they are not silently
  removed. CSV/JSON may still represent such input. Existing
  writer limits apply, including 2M text units, and can be stricter than import.
  No layout/Office visual fidelity, host copy qualification, print-ready,
  customer acceptance or delivery claim is made.

## Reproduce the focused CLI verification

```
python3 tests/typed_import_cli.py /absolute/external-build /absolute/fresh-evidence
```

Needs Python 3 and Node. The verifier performs actual CSV and TSV imports, all
three exports, independent CSV and XLSX ZIP/XML checks, existing production XLSX
reimport, a Boolean query, changed-schema output, XML character/newline boundaries, 60 refusal cases and a
valid retry. It retains commands, diagnostics, output bytes and unchanged source hashes.
The library tests are in `jsontable/typed_delimited_test.mbt`; run the `jsontable`
package with `--frozen --strip -j 1` and an external target. Serialize native tests
with the shared native lock and check the required free-space reserve first.
