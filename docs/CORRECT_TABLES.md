# Review and apply typed table corrections

MoonLeaf can now make a bounded batch of cell corrections by exact business keys.
A recipe states every original value and desired value. All keys, target columns,
and expected values must match before a fresh corrected table is returned. A
recipe-ordered report shows the source data-row number, key tuple, before/after
value and type, and changed/unchanged status. Source row/column order is retained.
This is useful for correcting selected customer names, statuses, amounts and notes
in an export without replacing whole rows or editing unrelated data.

## Run

Build with the pinned compiler and frozen dependencies, using an external target:

```
moon build cmd/correct cmd/preview --target js --frozen --strip -j 1 --target-dir /absolute/build
node /absolute/build/js/debug/build/cmd/correct/correct.js json kit/corrections/source.json kit/corrections/corrections.json report json > /fresh/review.json
node /absolute/build/js/debug/build/cmd/correct/correct.js json kit/corrections/source.json kit/corrections/corrections.json copy xlsx > /fresh/corrected.xlsx
node /absolute/build/js/debug/build/cmd/preview/preview.js /fresh/corrected.xlsx
```

Arguments: `csv|tsv|json|jsonl SOURCE RECIPE copy|report csv|json|xlsx`.
Both input paths must be explicit regular files; stdin is not accepted. Both copy
and report are fully computed before the selected output is serialized. Invalid
inputs produce a nonzero exit, stderr diagnostic and no dataset bytes on stdout.
The library returns `CorrectionResult { table, report }` from
`table.correct(parse_correction_recipe(recipe_json))`.

The adapter reads files and writes stdout only. Use new output destinations: shell
redirection can truncate an input or existing destination before MoonLeaf starts.
The host owns permissions, confirmation, destination selection, readback and source
conflict handling. Report and copy commands read separately; retain source/recipe
hashes and ensure neither changes between review and export. A matching key/old
value alone is not a whole-artifact identity check. No verified-copy, customer
acceptance, print-ready or delivery status is claimed by this command.

## Recipe

```
{"key_columns":["invoice_id","line_id"],"edits":[
  {"key":["INV-001","2"],"column":"customer",
   "before":{"type":"text","value":"old"},
   "after":{"type":"text","value":"New customer"}},
  {"key":["INV-001","2"],"column":"amount",
   "before":{"type":"number","value":"12.5"},
   "after":{"type":"number","value":"20"}}
]}
```

- `key_columns` supplies 1–32 distinct exact names. Each source row must have a
  nonempty text value in every key column. Tuples are globally unique, including
  unedited rows. Components are encoded without separator collisions. No trimming,
  case folding, Unicode normalization, fuzzy matching or numeric coercion occurs.
- `key` supplies the same number of exact strings in the same order. Leading zero
  IDs are preserved. Every edit must locate a source row and existing column.
- Every `before` and `after` is explicitly typed: `text` with string value,
  `number` with a finite JSON-number string, `boolean` with Boolean value, or
  `empty` with no value field. Empty and text `""` are distinct.
- Number preconditions compare the Table's exact numeric string, not numeric
  equivalence: `"1"` differs from `"1.0"`. JSON/JSONL intake uses the existing
  parser's normalized representation (for example 12.50 becomes 12.5); inspect
  the imported table first. CSV/TSV values are always text, even numeric-looking
  cells. An explicitly requested after value may change type.
- Key columns cannot be edited. Repeating a target cell is refused, including
  repeated no-op edits; edits are never chained. No-op edits are reported as
  `unchanged`. Any late failure refuses the whole batch without mutating input.
- Missing or unknown fields and unsupported cell types fail. JSON duplicate
  object keys retain the existing parser's last value; use unique object fields.

## Bounds and fidelity

Input table: 1–128 unique nonempty headers, rectangular rows, at most 10,000 data
rows and 100,000 cells including headers; total header/text/number strings at most
4,000,000 UTF-16 units. Key components and key-column names at most 4,096 units.
Recipe: at most 1,048,576 UTF-16 units, 1–1,000 edits. CLI: each regular input file
at most 8 MiB, source text at most 4,000,000 units before parsing. Reads are whole
file, not streaming; no hostile-input memory SLA. The input-string bound is not
an output bound: edits can grow the result by the bounded recipe content.

Only Empty, Text, finite Number and Boolean values are accepted. Formula and
Error cells are refused even when unedited; no calculation occurs. Existing JSON
intake represents null as text `"null"`, nested objects/arrays as compact text and
absent fields as Empty. Such text may be edited as text; this does not provide
nested JSON editing or preserve original JSON formatting.

CSV loses types and cannot distinguish Empty from empty text. Formula-looking
CSV strings may be interpreted by spreadsheet software. XLSX uses typed inline
text for text edits; no formula is created. JSON omits Empty fields and can lose
all-empty columns or an empty schema; numbers can normalize on serialization and
reopen. Report `before_type`/`after_type` retains the distinction when values are
blank or omitted, but serialized numeric spelling is not an exact source token
archive. Retain source and recipe. Exported XLSX is a newly created flat table,
not an in-place edit of an original Office workbook with styles or package parts.

This extends PRD W04/W06 bounded editing and review, not a complete graphical
MoonDesk save-as-copy journey. Source authenticity, full Office fidelity, provider
synchronization, customer acceptance and original-file overwrite are out of scope.

## Focused verification

```
moon test jsontable --target js --frozen --strip -j 1 --target-dir /absolute/build
flock /absolute/recovery/native-build.lock moon test jsontable --target native --frozen --strip -j 1 --target-dir /absolute/build
moon run tests/correct_cli.mbtx --target js --frozen --strip -j 1 --target-dir /absolute/build -- /absolute/build/js/debug/build/cmd/correct/correct.js /absolute/build/js/debug/build/cmd/preview/preview.js /absolute/fresh-evidence
```

Eight new functional tests exercise typed batch semantics, exact composite keys,
late conflicts/retry, nonmutation/output isolation, schema and target refusals,
scalar/export behavior, and inclusive row/column/cell/edit/text budgets. The real
CLI verifier creates synthetic source/recipe, exports and independently reopens
both outputs in all three formats, checks XLSX ZIP/inline text, exercises four
input formats and refusal paths, and compares original SHA256 before and after.
Actual canonical fixtures, outputs and reopen evidence are in `kit/corrections/`.

## Generate corrections for a pseudonymized sample

Use the [pseudonymized client-copy workflow](PSEUDONYMIZED_CLIENT_COPY.md) to
prepare this same recipe format from explicit column policies. It assigns
consistent per-file tokens or masks, preserves schema and row identity, and
leaves exact private before-values in the recipe for review. The client copy
contains no mapping, but may remain identifiable through other fields.

## Generate corrections by editing a normal sheet

The [review-sheet round trip](REVIEW_SHEETS.md) exports stable keys plus selected
editable CSV/TSV columns. Edit values and import the result as this same recipe,
without writing per-cell JSON. Sorting rows or reordering columns is supported;
key membership and column scope must stay exact. The fresh-copy adapter preserves
all unselected source cells, and the host still owns review and sharing.
