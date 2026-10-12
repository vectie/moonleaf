# Consolidate overlapping exports, with reviewable decisions

Choose exact text key columns and keep the first or last complete parsed row for
each key. Use this when regional or periodic exports overlap. Inspect the report
before using the selected copy. It is a row-selection tool: no fuzzy matching,
entity inference, merged fields, totals, accounting conclusions or changed originals.

## Try the synthetic four-source example

From this checkout, using the pinned toolchain and restored private dependencies:

```
moon build cmd/consolidate cmd/preview --target js --frozen --strip -j 1 --target-dir /absolute/external-build
node /absolute/external-build/js/debug/build/cmd/consolidate/consolidate.js strict first kept json '["id","region"]' north csv kit/consolidation/north.csv south tsv kit/consolidation/south.tsv web json kit/consolidation/web.json batch jsonl kit/consolidation/batch.jsonl > /fresh/path/kept.json
```

Change `first` to `last` to select the final occurrence. Change `kept` to `report`
to export every original parsed row with its disposition. Change output `json` to
`csv` or `xlsx`. The CLI accepts one to 64 LABEL FORMAT PATH triples; formats are
`csv`, `tsv`, `json` (object array) and `jsonl`. Labels must be nonempty and unique.
`strict` aligns identical header sets, including reordered TSV columns; `union`
adds first-seen headers and preserves absent values as blank `Empty` cells.

The 15-row example has nine distinct composite keys. `001`/`北` occurs five times.
Keep-first selects north data row 1; keep-last selects batch data row 4. `001`
and `1`, `a|b`/`c` and `a`/`b|c`, and composed/decomposed accented text stay distinct.
Actual outputs for both policies and both tables, all three formats, parser
reopen results and the exported XLSX worksheet XML are under `kit/consolidation/`.
All files are synthetic. `union-kept.json` separately demonstrates a final sparse
row replacing a fuller earlier row without filling from the discarded row.

## Review the report

Both tables preserve all source fields plus stack's `_source` and `_source_row`.
The latter is a one-based parsed data-row index within that input, excluding CSV/
TSV headers and blank JSONL lines; it is not a physical line/byte offset or proof
of authenticity. Four trailing report fields explain every decision:

- `_input_row`: one-based position across stacked sources, in argument order
- `_disposition`: `unique`, `kept` (winner of a duplicate group) or `discarded`
- `_kept_input_row`: `_input_row` of the complete selected row; follow this report
  row to inspect the selected `_source`, `_source_row` and values
- `_group_size`: exact count sharing that composite key, including this row

The report stays in complete original input order. Kept rows retain their relative
input order, including keep-last; groups are not sorted by key or first encounter.
Discarded rows remain in the report. The CLI emits the explicitly chosen table;
generate kept and report with the same inputs/options for a paired review.

## Library

```
let result = table.consolidate(
  key_columns=["id", "region"],
  retention=@jsontable.KeepLast,
)
// result.kept and result.report are independently mutable fresh tables.
```

Every key component must be nonempty `Text`. Missing, empty, numeric and Boolean
keys fail; whitespace is significant and allowed. There is no trimming, case
folding, Unicode normalization, date/number interpretation or delimiter-based
tuple collision. All rows are validated before selection, including discarded
rows. Formula/error cells and malformed/nonfinite `Number` values fail. Valid
numeric representations, scalar types and missing-versus-empty values are kept
unchanged in memory. Conflicting non-key values do not merge or raise: the chosen
complete row wins and the report exposes all alternatives.

Inputs must have unique nonempty headers and rectangular rows. Report names
above are reserved. CLI inputs also cannot already contain stack's `_source` or
`_source_row`; library callers can use stack's custom provenance column names.
Header-only CSV/TSV is supported. JSON `[]` has no schema and is refused by stack.

## Bounds, files and export limitations

- Library: 1–32 distinct key columns, 1–252 input columns, at most 10,000 input
  data rows, and at most 100,000 report cells including its header. The report has
  four extra columns. CLI stacking adds two more, so at most 250 source columns.
  Limits apply before deduplication, even if all rows share a key.
- CLI: regular UTF-8 input files only, no stdin; at most 8 MiB per file and
  8,388,608 combined UTF-16 code units; key JSON at most 65,536 code units. This is
  bounded in-memory processing, not streaming or an adversarial memory SLA.
- Inputs are read only. Validation and selected-table serialization finish before
  stdout is written. Errors exit nonzero with no dataset output. Shell redirection
  can truncate a destination before execution: always use a fresh path distinct
  from every input, and check exit status. Keep original files for later review.
- Complete *parsed* rows are retained. Existing JSON intake projects explicit
  null/nested values to literal text and parses numbers through its numeric model;
  it is not an arbitrary-precision or lossless original-JSON codec. A JSON null
  key becomes text `null`, so it cannot be distinguished from that literal string.
- JSON export omits `Empty` fields, normalizes numeric output and can lose all-
  missing columns or empty-table schema on reimport. CSV collapses missing and
  empty, loses scalar typing and leaves formula-like text unchanged. Spreadsheet
  applications may interpret CSV formulas; use typed XLSX for untrusted text.
  XLSX keeps supported scalar types and writes `=1+1` as inline text, not a formula.

## Reproduce the checks

```
moon test jsontable --target js --frozen --strip -j 1 --target-dir /absolute/external-build
moon test jsontable --target native --frozen --strip -j 1 --target-dir /absolute/external-build
moon run tests/consolidate_cli.mbtx --target js --frozen --strip -j 1 --target-dir /absolute/external-build -- /absolute/external-build/js/debug/build/cmd/consolidate/consolidate.js /absolute/fresh-synthetic-kit /absolute/external-build/js/debug/build/cmd/preview/preview.js /absolute/fresh-evidence
```

Use private HOME/XDG, `MOON_DEP_CACHE=off`, `MOON_BUILD_CACHE=off`; serialize native
commands under the recovery native-build lock. The verifier needs Node and unzip.
It compares every retained row and disposition, reopens every export with existing
parsers/preview, verifies ZIP/inline-text XML and original input hashes, exercises
schema/key/UTF-8/file/row limits and proves a successful retry after refusals.
No MoonDesk, graphical host, Mac, provider, deployment or full-suite claim is made.
