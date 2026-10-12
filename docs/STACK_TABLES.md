# Combine exports with row provenance

Stack appends multiple datasets by exact header names, retaining source order and
row order. This fills a gap between existing single-table pivot/unpivot and
key-based lookup: combining regional exports or periodic batches without a join.
All examples are synthetic, not customer data. No host acceptance or fidelity
status changes are implied.

For overlapping exports, [consolidation](CONSOLIDATE_TABLES.md) adds explicit
exact-text composite keys, keep-first/keep-last selection and a complete
source-linked disposition report after stacking. Ordinary stack still keeps all rows.

## File workflow

Build `moon build cmd/stack --target js --frozen --strip -j 1` and run:

```
node _build/js/debug/build/cmd/stack/stack.js union json north csv docs/samples/stack/north.csv south tsv docs/samples/stack/south.tsv web json docs/samples/stack/web.json batch jsonl docs/samples/stack/batch.jsonl > combined.json
```

Choose `strict` or `union` explicitly, followed by output `csv`, `json` or `xlsx`,
then one or more LABEL FORMAT PATH triples. Input formats are `csv`, `tsv`, `json`
(object array) and `jsonl`. Every path is a UTF-8 file; stdin `-` is not accepted.
The six-row result and actual CSV, JSON and XLSX outputs are in
[samples/stack/output](samples/stack/output). The first two inputs also work in
strict mode even though the TSV headers are reversed. All four in strict mode
fail because only the web source has `active`.

Source labels are required, nonempty and unique. They are supplied provenance,
not file digests or authenticity claims. Repeating a file under different labels
is allowed and duplicates its records. `_source` is the label and `_source_row`
is the one-based data row within that file, excluding the header. Output goes to
stdout only after complete parsing, validation and serialization; errors exit 1
with stderr and no partial dataset. Shell redirection may truncate a destination
before execution; choose a fresh copy path and inspect exit status.

## Library

```
let combined = @jsontable.stack(
  [first, second],
  sources=["north", "south"],
  mode=@jsontable.StrictHeaders,
)
```

- `StrictHeaders` requires identical header sets, aligning reordered columns to
  the first source's order. `UnionHeaders` adds new headers in first-seen order
  and fills absent cells with `Empty`. Neither mode drops rows or deduplicates.
- All headers must be unique and nonempty and every source rectangular with at
  least one header. Header-only sources contribute their schema. JSON `[]` has
  no schema and is refused.
- `source_column` and `row_column` optionally rename the two trailing provenance
  fields in library calls. Names must be nonempty, distinct, and absent from
  every source. The CLI uses the defaults and refuses collisions.
- Input arrays are never mutated. Output columns and each output row are new.
  Text, numeric representation, booleans and `Empty` remain unchanged in memory.
  CSV/TSV imports stay text, including leading zeros and empty strings. JSON
  numbers/booleans retain types; the existing parser represents explicit null
  and nested values as literal text. Missing and empty text stay distinct.
- Formula/error cells are refused, not recalculated or relocated. Formula-looking
  text stays text. CSV consumers may infer types or execute formulas; typed XLSX
  or JSON is preferable for untrusted text.
- JSON output omits `Empty` properties. This preserves missing-versus-empty but
  can change inferred header order on reimport and loses all-missing columns and
  empty-table schemas. Numeric JSON serialization follows existing exporter
  behavior. CSV collapses missing to empty text and loses scalar typing. XLSX
  preserves supported scalar types and blanks within existing writer limits.
- Limits: 1–64 sources; at most 256 output columns including provenance; 10,000
  output data rows; 100,000 output cells including the header. Existing parser
  and exporter limits still apply. This is bounded in-memory processing, not
  streaming or a large-file resource guarantee. Host file access and source
  retention remain outside the transformation library.

## Replay checks

`moon test jsontable --target js --frozen --strip -j 1` and the same command with
`--target native` exercise the library, including exported XLSX reopen.

```
moon run tests/stack_cli.mbtx --target js -- /absolute/build/js/debug/build/cmd/stack/stack.js /absolute/moonleaf/docs/samples/stack /absolute/existing-evidence-directory
```

The MoonBit script executes the real CLI for all four input formats, all three
outputs, reordered strict success, and strict mismatch refusal. Use
`--target-dir /absolute/build` to keep compiler artifacts outside the checkout.
The native library is portable; the file CLI and replay script require Node.
