# Compare two data snapshots

Find added accounts, removed inventory records, changed amounts and unchanged
records between two exports. Reconciliation is a new review dataset, not an
edit, merge or approval of either input. The existing lookup enriches records
from a reference table; this workflow compares both complete snapshots and
retains before/after values and row references.

## File workflow

Build the Node CLI from this module:

```
moon build cmd/reconcile --target js --frozen --strip -j 1
node _build/js/debug/build/cmd/reconcile/reconcile.js all json '["account","region"]' csv docs/samples/reconcile/before.csv tsv docs/samples/reconcile/after.tsv > review.json
```

Choose `all` or `changes`, output `csv`, `json` or `xlsx`, a JSON array of key
column names, then BEFORE_FORMAT BEFORE_PATH AFTER_FORMAT AFTER_PATH. Each input
may independently be `csv`, `tsv`, `json` (object array) or `jsonl`. Explicit UTF-8
file paths are required; stdin `-` is refused. Quote the key array for your shell.
Output goes to stdout after full validation and serialization. Failures are
nonzero with stderr and no partial dataset. Shell redirection may truncate its
destination before the command starts: use a new copy path and inspect exit
status. Input files are read only.

The synthetic sample produces four records in this order:

- `001` / `北`: unchanged, before row 1 and after row 2
- `002` / `南`: changed amount `20` to `25`, before row 2 and after row 1
- `003` / `東`: removed, before row 3 and no after row
- `004` / `西`: added, no before row and after row 3

`changes` omits unchanged rows while preserving original row references. Actual
CLI outputs are in [samples/reconcile/output](samples/reconcile/output), with
typed JSON/JSONL examples too. All samples are synthetic.

## Library contract

```
let review = before.reconcile(
  after,
  key_columns=["account", "region"],
  include_unchanged=false,
)
```

Either table can come from an existing table parser. The library works on native
and JS. It validates both inputs before comparing:

- Exact identical header sets are required, with unique nonempty names and
  rectangular rows. Reordered headers are aligned by name. Added, removed or
  renamed columns are deliberately refused, even if no rows would be returned.
  Reconcile schema changes separately rather than treating missing columns as
  ordinary blanks. A header-only CSV/TSV or manually constructed table works;
  JSON `[]` lacks a schema and is refused.
- Keys are one or more unique named columns, with exact nonempty text in every
  component of every row. Keys must be unique within each snapshot. Duplicate,
  empty, missing, numeric and boolean keys are refused with side and data-row
  diagnostics. Composite keys encode component boundaries, so separators,
  quotes, newlines and Unicode in key text do not cause collisions. There is no
  trimming, case folding, numeric coercion or fuzzy matching. A key value change
  appears as removal plus addition. There is no many-to-many row multiplication.
- All non-key columns are compared. Values use exact `CellValue` equality:
  missing `Empty`, empty text, numeric text representation, text and booleans
  remain distinct. Manually supplied `Number("1")` and `Number("1.0")` differ.
  There is no numeric tolerance, rounding, date interpretation or recalculation.
  CSV/TSV cells are text, so a JSON numeric value and CSV numeric-looking text
  compare as changed. JSON intake retains its existing projection: explicit
  null and nested values become literal text and may equal an actual string
  with that text. Use explicit string identifier fields; reconciliation cannot
  recover distinctions already lost during parsing.
- Formula and error cells anywhere in either input are refused, including when
  `include_unchanged=false`. Formula-looking text stays text. Inputs and their
  column/row arrays are not mutated; each result array is a new copy.

Output starts with the key columns in requested order, then `_change`,
`_before_row`, `_after_row`, followed by paired `before.NAME`, `after.NAME` columns
for every non-key column in the before table's order. Output name collisions
are refused. Status is `added`, `removed`, `changed` or `unchanged`. Row references
are one-based data rows excluding the header. A missing side uses `Empty` for
its row reference and values. Result order is before-row order followed by added
rows in after-row order. Row references identify these immediate snapshots,
not file digests, authenticity or a persistent record identity.

## Export and spreadsheet safety

- JSON output omits `Empty` properties, preserving missing versus empty strings
  and supported scalar types. Reimport can change column order and lose
  all-missing columns or an empty-table schema. Numeric serialization follows
  the existing exporter, not a byte-exact numeric-lexeme contract.
- CSV output is raw quoted data. Quoting protects delimiters and newlines; it
  does not prevent spreadsheet formula interpretation. For example, the sample
  exports `=1+1` literally. This CLI does not add an apostrophe or offer a
  spreadsheet-safe CSV mode. CSV also collapses missing/empty and loses scalar
  types. Do not open untrusted raw CSV in a formula-executing spreadsheet without
  an explicit text-only import or a separately reviewed sanitization step.
- XLSX output preserves supported numbers, booleans, text and blanks through
  MoonLeaf's writer. Formula-looking text is emitted and reopened as text, not
  a formula. This is a new simple workbook, not preservation of source workbook
  formatting, formulas, charts, relationships or signatures.

Each input is limited to 1–256 columns, 10,000 data rows and 100,000 cells including
the header. The result is limited to 256 columns, 10,000 rows and 100,000 cells
including the header. Paired columns consume this limit, so a 127-column table
with one key is the widest supported result. With more keys, more input columns
can fit. Filtered unchanged rows do not consume output rows but all input limits
and validation still apply. Existing parsers and exporters impose their own
limits. Files and values are in memory; there is no streaming or arbitrary-file
resource guarantee.

Host file permissions, retained originals, source digests, destination conflicts,
visual acceptance and customer approval remain host responsibilities. This
workflow does not add a MoonDesk control or qualify full Office fidelity.

## Replay checks

```
moon test jsontable --target js --frozen --strip -j 1
moon test jsontable --target native --frozen --strip -j 1
moon build cmd/reconcile cmd/preview --target js --frozen --strip -j 1
moon run tests/reconcile_cli.mbtx --target js --frozen --strip -j 1 -- /absolute/build/js/debug/build/cmd/reconcile/reconcile.js /absolute/moonleaf/docs/samples/reconcile /absolute/existing-evidence-directory /absolute/build/js/debug/build/cmd/preview/preview.js
```

Use `--target-dir /absolute/build` to keep build artifacts outside the checkout.
The replay executes both input pairs, all three outputs, the changes filter,
actual XLSX reopen through the existing preview reader, five fail-closed
refusals, successful retry and unchanged input contents. Library tests additionally
check typed XLSX values, composite-key collisions, shape/ambiguity refusal and
input/output limits. These are focused synthetic checks, not full host or
all-target acceptance.
