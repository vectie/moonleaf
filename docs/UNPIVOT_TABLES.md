# Turn wide exports into tidy rows

Monthly sales, budgets and survey exports often put each month or question in a
separate column. Unpivot repeats the identifying fields and moves selected column
names and values into two columns, ready for filtering in another app, a lookup,
or MoonLeaf's existing grouped summaries. It creates a new dataset; it does not
rewrite the original file or add a MoonDesk control.

## Run on a file

Build the Node executables from the module root:

```
moon build cmd/unpivot cmd/summarize --target js
node _build/js/debug/build/cmd/unpivot/unpivot.js csv docs/samples/unpivot/tidy-sales.json csv < docs/samples/unpivot/monthly-sales.csv > tidy-sales.csv
node _build/js/debug/build/cmd/summarize/summarize.js csv docs/samples/unpivot/monthly-totals.json json < tidy-sales.csv > monthly-totals.json
```

Use the chosen target directory instead of `_build` when building with
`--target-dir`. The reusable unpivot specification is:

```
{
  "id_columns": ["store", "region"],
  "value_columns": ["Jan", "Feb", "Mar"],
  "names_to": "month",
  "values_to": "sales",
  "drop_empty": true
}
```

The included three-store fixture produces seven records with columns
`store, region, month, sales`. Store `001` has Jan 100 and Feb 120; missing March
is omitted. Store `002`'s January zero is retained. Monthly totals are Jan 150,
Feb 195 and Mar 70, with 3, 2 and 2 reporting stores respectively.

CLI arguments are INPUT_FORMAT, SPEC_PATH and OUTPUT_FORMAT. Inputs are `csv`,
`tsv`, `json` (object array) or `jsonl`. Outputs are `csv`, `json` or `xlsx`.
For example, change the final argument to `xlsx` and redirect stdout to a fresh
`.xlsx` filename. Input is UTF-8 stdin; the spec is a UTF-8 file. Output is fully
computed before writing stdout. Errors exit nonzero with stderr and no partial
data result. Shell redirection can still create, truncate or fail to write a
destination: choose a new path and check the exit status.

## Use the library, including native hosts

```
let tidy = table.unpivot(
  id_columns=["store", "region"],
  value_columns=["Jan", "Feb", "Mar"],
  names_to="month",
  values_to="sales",
  drop_empty=true,
)
let csv = tidy.export_csv()
let json = tidy.export_json(omit_empty=true)
let xlsx = tidy.export_xlsx()
```

`Table::unpivot` works with the same Table returned by JSON, JSONL, CSV/TSV,
[XML record intake](XML_RECORDS.md), lookups and summaries. It can feed
`Table::summarize`, `lookup` or `workbook` directly. It does not require Node;
`moon run examples/unpivot --target native -- --summary` runs the synthetic
monthly-sales-to-summary workflow. Without `--summary`, the example prints the
tidy CSV; `--xlsx-base64` prints its XLSX bytes as base64.

## Exact transformation rules

- Both column lists are required. `id_columns` can be empty; `value_columns`
  cannot. Names are exact and case-sensitive, and the two lists must contain
  distinct, existing columns without overlap. Unselected source columns are
  deliberately omitted. Selecting identifiers in a different order changes the
  output order. Duplicate identifier values are retained as separate rows.
- Output follows input row order, then the requested value-column order. Each
  result has the selected identifiers, the original value-column name as text,
  and the original value. No date, number or locale inference occurs.
- `names_to` defaults to `variable`; `values_to` defaults to `value`. These names
  must be nonempty and distinct from each other and the output identifiers.
- `drop_empty` defaults to false, retaining all selected values. If true, it
  drops only missing (`Empty`) cells and exact empty text, not whitespace, zero,
  false or the text `null`. Existing JSON intake projects null and nested values
  to literal text, so they are retained. CSV/TSV values stay text; JSON numeric
  and boolean types survive JSON and XLSX output.
- Selected formula/error cells are refused with their one-based data row and
  column. This is a scalar dataset reshape, not formula relocation or workbook
  recalculation. Formula-looking text remains text; spreadsheet apps may
  interpret it when opening CSV. Use typed XLSX or JSON for untrusted text.
- All result arrays are fresh. Input arrays, identifiers and selections are not
  modified. Empty input retains the output columns, although JSON `[]` cannot
  preserve an empty schema. JSON output omits missing properties, preserving
  their distinction from empty strings on reimport when the field occurs in
  another record. CSV cannot preserve missing-versus-empty distinctions.

The operation accepts at most 10,000 input rows, 256 columns and 100,000 input
cells. Output is limited to 10,000 data rows, 256 columns and 100,000 cells
including the header; omitted empty values do not count toward output limits.
Existing CSV parsing and XLSX writer limits also apply. CLI input is read into
memory; this is not a streaming processor or a large-file resource guarantee.
No dependency was added. File access, save destinations and source retention
remain host responsibilities.
