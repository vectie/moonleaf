# Group and summarize imported tables

Answer questions such as “How many orders and how much revenue did each region
and product generate?” without writing formulas or changing an imported file.
MoonLeaf now produces a reusable, long-form summary table from CSV, TSV, JSON or
JSON Lines. This is a library and Node CLI workflow; it does not add a MoonDesk UI.

## Run the CLI on a file

Build the JavaScript executable from the module root:

```
moon build cmd/summarize --target js
node _build/js/debug/build/cmd/summarize/summarize.js csv docs/samples/summary/by-region-product.json csv < docs/samples/summary/sales.csv > sales-summary.csv
```

The usual default output directory is `_build`. If using `--target-dir`, replace
`_build` with that directory. The round handoff gives exact frozen pinned-toolchain
commands used for verification.

Arguments are INPUT_FORMAT, SPEC_PATH, OUTPUT_FORMAT, in that order. Input comes
from stdin; results go to stdout. INPUT_FORMAT is `csv`, `tsv`, `json` (object
array), or `jsonl`. OUTPUT_FORMAT is `csv` or `json`. No source is written. Shell
redirection controls the destination and can overwrite an existing file, so pick
a new output path. On an error, the CLI exits nonzero and writes an error to stderr,
with no partial result on stdout.

A saved spec can be reused on the next export with the same column names:

```
{
  "group_by": ["region", "product"],
  "measures": [
    {"name": "orders", "op": "count"},
    {"name": "revenue", "op": "sum", "column": "amount"},
    {"name": "average_sale", "op": "mean", "column": "amount"}
  ]
}
```

The included sales sample yields East/Tea: 3 orders, revenue 160, average 80.
One order has a blank amount, so it counts as an order but not in the average.
East/Coffee has one order, sum zero and no average. JSON represents that missing
average as `null`; CSV leaves it blank. The five groups retain first-seen order.
`grand-total.json` uses `"group_by": []` to summarize all eight orders in one row.
Change grouping and measure names to explore the same input from another angle.

## Use the library

```
let sales = @jsontable.parse_delimited(text)
let summary = sales.summarize(
  group_by=["region", "product"],
  measures=[
    { name: "orders", operation: @jsontable.CountRows },
    { name: "revenue", operation: @jsontable.Sum("amount") },
    { name: "average_sale", operation: @jsontable.Mean("amount") },
  ],
)
let csv = summary.export_csv()
let json = summary.export_json()
let xlsx = summary.export_xlsx()
```

The result is a fresh `Table`, with group columns first and named measures next.
Existing workbook preview, CSV and typed XLSX export work on it. Grouping can also
follow `Table::lookup` to summarize orders by enriched customer metadata. No
source or spec arrays are modified. A summary can itself be summarized to add
subtotals; sum the counts and sums rather than averaging averages with unequal
sample sizes.

## Rules that affect results

- CSV/TSV requires a unique nonempty header and rectangular data rows. Fields
  stay text on import. Only explicitly selected numeric measure columns are parsed.
- Text keys use exact case and whitespace. `001`, `1`, ` A ` and `A` are distinct.
  Missing, empty text, number and boolean keys are distinct types. Numeric keys
  use their finite double-precision value (`1` and `1.0` share a group); the first
  spelling is retained in the result. Keep large identifiers as text strings.
- Count counts every row. Sum and mean ignore missing cells and text empty after
  ASCII space/tab/newline trimming. Mean divides by the number of nonblank numeric
  cells, independently for each measure. Sum of no numeric values is zero; mean
  of no numeric values is blank.
- Numeric text uses finite JSON number syntax, including negatives, decimal
  fractions and scientific notation, with optional surrounding ASCII whitespace.
  Currency symbols, thousands separators, leading `+`, leading zeros, booleans,
  `null`, `NaN`, infinity and formula cells are errors. Errors name the one-based
  data row and source column; overflow names the output measure. Data row 1 is
  immediately after a CSV/TSV header. JSONL row numbers count parsed objects.
- Arithmetic uses double precision with compensated summation, not exact decimal
  accounting. Values beyond exact double precision may round, and overflowing
  sums fail even when a mathematical mean could fit. No formula evaluation,
  currency/date coercion or locale inference occurs.
- Group and measure names must exist and output names must be unique/nonempty.
  At least one measure is required. Empty input with group columns returns no
  rows; empty input with no group columns returns one grand-total row.
- The existing JSON parser projects JSON null and nested objects/arrays to text.
  Such values are not numeric blanks. Use missing/empty fields for absent measures.
  JSON export preserves Table text/number/boolean types and writes empty cells as
  null; it refuses formula/error cells. Reimporting its nulls follows that older
  projection, so JSON export is an interchange format, not a lossless Table codec.
- CSV export preserves cell text and quotes every field. Spreadsheet applications
  may interpret formula-like text; prefer typed XLSX or JSON for untrusted text.

## Scope and limits

Summaries allow at most 10,000 data rows, 256 input/output columns, 100,000 input
cells and 100,000 output cells including the header. CSV/TSV parsing has existing
stricter limits: 2,097,152 UTF-16 code units, 10,000 total rows including the header,
256 columns and 100,000 cells. Existing XLSX writer limits still apply.

This is an in-memory long-form group-by, not a two-dimensional pivot grid,
database query engine or streaming processor. It creates a new dataset rather
than rewriting a source workbook. File identity, destinations and host UI remain
host responsibilities. Parsing and numeric tests do not establish Office visual
fidelity, performance at database scale, or an accounting-grade decimal model.

Mapped [XML records](XML_RECORDS.md) also produce a Table directly. The XML CLI's
JSON export omits missing fields, so it can feed this summary CLI without changing
missing numeric values into literal `null` text. For library export, opt into
`export_json(omit_empty=true)`; keep the original column list when every value in a
column is missing or there are no rows.
