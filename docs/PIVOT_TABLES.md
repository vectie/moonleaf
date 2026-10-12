# Turn long observations into a wide comparison

Sales exports and repeated survey answers often contain one record per entity
and period or question. Pivot makes a new table with one row per selected ID
and one column per observed key. It makes a spreadsheet-friendly comparison
without guessing which records to combine or silently aggregating duplicates.

## Run on a file

From the module root:

```
moon build cmd/pivot --target js
node _build/js/debug/build/cmd/pivot/pivot.js csv docs/samples/pivot/wide-sales.json csv < docs/samples/pivot/monthly-sales.csv > wide-sales.csv
```

Use your chosen `--target-dir` instead of `_build` when applicable. The spec is:

```
{"id_columns":["store","region"],"key_column":"month","value_column":"sales"}
```

The sample produces `store,region,Feb,Jan,Mar`, in first-seen month order:

| store | region | Feb | Jan | Mar |
| --- | --- | --- | --- | --- |
| 002 | West | 75 | 0 | 80 |
| 001 | North | | 100 | 120 |
| 003 | North | | 50 | |

CLI arguments are INPUT_FORMAT, SPEC_PATH and OUTPUT_FORMAT. Inputs are UTF-8
`csv`, `tsv`, `json` (object array), or `jsonl` on stdin. Outputs are `csv`,
`json`, or `xlsx` on stdout. Change the final argument to `xlsx` for a typed
spreadsheet copy. The spec comes from a UTF-8 file. Parsing, pivot and export
finish before stdout is written; failures exit nonzero and report stderr.
Shell redirection can still create/truncate a destination or fail during a
write. Choose a fresh output path and check the exit status.

## Duplicate cells are a choice

A duplicate is a repeated exact ID tuple and key, including identical values,
missing values and empty text. The default `"duplicates":"reject"` reports
both one-based input data rows and the key. Correct the source or choose:

- `"first"`: retain the earliest row's value, including an empty value
- `"last"`: retain the last row's value, including an empty value

For an ordered correction feed, `latest-sales.json` and `corrections.csv`
produce store 001 with Jan 110 and Feb 120; store 002 retains Jan 0. These
policies use input order, not dates or version fields. No total is calculated.
If duplicate observations should be summed, first explicitly summarize by
ID columns plus the key column using `Table::summarize`, then pivot its sum.

## Native or other library hosts

```
let wide = table.pivot(
  id_columns=["store", "region"],
  key_column="month",
  value_column="sales",
  duplicates=@jsontable.Reject,
  prefix="",
)
let csv = wide.export_csv()
let json = wide.export_json(omit_empty=true)
let xlsx = wide.export_xlsx()
```

`Table::pivot` works with `@jsontable.Table`, including results from the existing
CSV/TSV/JSON/JSONL intake, XML record mapping, lookups, summaries and unpivot.
The API is portable; only this CLI uses Node. The result can feed `workbook`
or another table operation directly. No new MoonDesk controls are included.

## Exact behavior and boundaries

- All three selections are required. Names are exact, case-sensitive, unique,
  present and disjoint. Unselected fields are omitted. `id_columns:[]` groups
  all observations into one output row when input is nonempty.
- ID columns follow requested order, rows follow first-seen ID tuple order,
  and new headers follow first-seen key order. First/last duplicate resolution
  never changes those orders. There is no sorting or date inference.
- IDs are grouped by exact scalar type and payload: missing, empty text,
  number, text and boolean stay distinct. Composite keys cannot collide because
  of delimiters. For manually constructed Number cells, `"1"` and `"1.0"` are
  distinct lexical payloads; existing JSON intake may normalize number text.
- Pivot keys must be nonempty text. Missing/empty, numeric, boolean, formula
  and error keys fail instead of being coerced to labels. Whitespace, Unicode,
  punctuation and case remain exact. Optional `prefix` is prepended to every
  key-derived header; use it to avoid a collision with an ID column. Header
  collisions fail rather than overwriting data.
- Missing ID values group together. A missing ID and empty text are different
  groups. An absent ID/key combination becomes `Empty`, not zero. An explicitly
  missing selected value and an absent combination both export as missing, but
  an input row with missing value still counts for duplicate detection.
- Values retain scalar type and content, including empty text, whitespace,
  zero and false. Existing JSON intake maps null and nested objects/arrays to
  literal text. Selected formulas and error cells fail, including discarded
  duplicates under `first`. Formula-looking text remains text. Spreadsheet
  apps may interpret such text when opening CSV; choose typed XLSX or JSON for
  untrusted text. This does not move formulas, recalculate, or edit a workbook.
- Input tables must be rectangular with unique nonempty headers. The in-memory
  pivot allows at most 10,000 input/output rows, 256 input/output columns and
  100,000 input cells; the output's 100,000-cell limit includes the header.
  Widening is checked as keys and groups appear, before dense allocation.
  Existing parsing and export limits also apply. CLI input is read fully before
  table validation; this is not a streaming or general hostile-input boundary.
- Arrays are fresh and input is never changed. Empty input yields selected ID
  headers and no data rows; no key-derived headers can be inferred. With no IDs
  it has no schema. JSON `[]` cannot retain an empty schema. JSON output omits
  missing properties; an entirely missing column may disappear when reimported.
  CSV merges missing/empty cells and loses scalar types. XLSX preserves the
  supported scalar values, but no Office visual-fidelity claim is made.
