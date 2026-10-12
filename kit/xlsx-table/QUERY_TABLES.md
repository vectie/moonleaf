# Reuse a table query recipe

Select a useful inspected copy from an existing CSV, TSV, JSON object-array or
JSONL export. Save the JSON recipe once, apply it to later exports with the same
column names, and send the resulting values to CSV, JSON or a simple XLSX.
The original input and recipe are never edited.

## Run

Build `moon build cmd/query --target js --frozen --strip -j 1` using the pinned
project toolchain. With the emitted JavaScript path substituted:

```
node query.js csv kit/query/input.csv kit/query/recipe.json json > reviewed.json
node query.js tsv kit/query/input.tsv kit/query/recipe.json csv > reviewed.csv
node query.js jsonl kit/query/input.jsonl kit/query/recipe.json xlsx > reviewed.xlsx
```

Use a distinct destination. Shell redirection creates/truncates it before the
program starts; the CLI cannot protect a path chosen by the shell. There is no
in-place writing, stdin, UI or integration action. The CLI finishes validation
and serialization before writing dataset bytes to stdout. Failures exit nonzero.

`kit/query/recipe.json` demonstrates this complete reusable recipe:

```json
{
  "version": 1,
  "filters": [
    {"column":"note", "mode":"text", "op":"ne", "value":"skip"},
    {"column":"score", "mode":"number", "op":"ge", "value":2}
  ],
  "sort": [
    {"column":"team", "mode":"text", "direction":"asc", "blanks":"last"},
    {"column":"score", "mode":"number", "direction":"desc", "blanks":"last"}
  ],
  "select": ["id", "score", "note"],
  "limit": 3
}
```

The result has IDs 002, 004, 001: first keep every row satisfying all filters,
then sort by team and descending score, then take three rows and project the
three selected columns. Equal complete sort keys retain original input order.
An empty filter or sort list is allowed. Selection is explicit, nonempty and
ordered; duplicate names and unknown columns fail. All five top-level fields
and all fields in each filter/sort object are mandatory; unknown fields fail.

## Comparison contract

- `text` requires text cells and text comparison values. Comparison is exact,
  case-sensitive UTF-16 lexicographic order, without locale/case/whitespace
  normalization. `contains` is a literal substring test, not a regex.
- `number` explicitly opts into parsing Number cells or text as finite JSON
  numbers using IEEE-754 Double. JSON surrounding whitespace is accepted;
  leading-zero forms such as `001`, currency, commas, booleans, NaN and Infinity
  fail. Scientific notation works. Numeric comparison can round large integers;
  use text mode for exact identifiers. Stored cells retain their original types
  and spelling: number mode does not rewrite the selected data.
- `boolean` requires actual boolean cells/literals; false sorts before true.
  CSV/TSV strings `true` and `false` are not implicitly converted.
- `eq`, `ne`, `lt`, `le`, `gt`, `ge` work in all three modes; `contains` only in
  text mode. Blank cells never match these comparisons, including `ne`.
- `is_blank` / `not_blank` require `value: null`. They test blankness regardless
  of the declared valid mode. Blank means missing (`Empty`) or empty text (`""`);
  whitespace-only text is present. Sorts group missing and empty text together,
  retain their order on complete ties, and honor `blanks: first|last` independently
  of `direction: asc|desc`.
- Existing JSON imports represent JSON null as literal text `"null"`, not blank,
  and nested JSON as compact text. Real JSON null and the string `"null"` cannot
  be distinguished after that existing import projection. Use text equality to
  select the projected value; number mode rejects it.

All source cells are checked for unsupported formula/error variants, and all
comparison/sort values are validated even in filtered-out rows or when limit=0.
A bad row cannot be hidden by another filter. This is a value-table query, not a
formula engine, locale-aware database, streaming pipeline or source-authenticity
check.

## Bounds and library API

The recipe is at most 65,536 UTF-16 code units, 32 AND filters, 8 unique sort keys,
1–256 unique projected columns, and an explicit integer limit 0–10,000. The
input needs 1–256 unique nonempty columns, rectangular rows, at most 10,000 data
rows and 100,000 cells including the header. Projection and limit cannot expand
these output budgets. Limit=0 returns headers without rows; a positive limit
intentionally truncates after sorting. The CLI emits the limited dataset only.

`parse_query_recipe(text)` returns an opaque `QueryRecipe`; `Table::query(recipe)`
returns `QueryResult { table, source_rows, matched_rows }`. `source_rows` are
one-based data-row positions after sorting/limiting; `matched_rows` counts all
matches before the limit, allowing a host to show truncation. The parsed recipe
can be reused without reparsing or mutated internals.

The Node CLI accepts UTF-8 inputs up to 8 MiB (checked after reading). Import
parsing precedes table size validation. This is bounded in-memory functionality,
not a hostile-input resource or performance SLA. No new dependency is used.

## Output limits

CSV is quoted raw text, not spreadsheet-formula-safe CSV; external spreadsheets
may interpret formula-looking strings. XLSX preserves those strings as text in
a fresh simple workbook; it does not preserve an original workbook's styling,
formulas or metadata. JSON omits missing cells but retains empty strings and
existing projected null/nested text; empty output arrays cannot carry a schema.
JSON/CSV round trips have those existing representation limits. Inspect output
before delivery; successful reopen is not full Office fidelity or acceptance.

The synthetic kit includes actual CLI outputs and CSV/JSON/XLSX reopen results.
Tests cover JS and native library execution and real Node file operations; no
MoonDesk UI, live provider or graphical Office validation is claimed.
