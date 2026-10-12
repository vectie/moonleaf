# Edit selected CSV/TSV columns in a review sheet

A reviewer can now edit ordinary CSV or TSV instead of writing one JSON object
per corrected cell. Export stable row identifiers and the columns that may change,
edit that small sheet, then import its changed cells as the existing MoonLeaf
[typed correction recipe](CORRECT_TABLES.md). Optionally [accept or reject individual proposed changes](SELECT_REVIEW_EDITS.md)
before applying. Apply the proposal to a fresh copy
of the original full table, retaining all other columns and the original row order.

For example, a customer-support lead can correct names and statuses without
handling an export's internal notes column. Sorting the review sheet or moving
its columns does not change which source record receives each correction.
This is a local file-host adapter, not a collaborative editor or a permission
system. The sheet's values are proposals until the caller reviews them.

## Three-step workflow

Use Python 3.10 or newer from a MoonLeaf checkout. Only its standard library is
needed. Each destination directory/file below must be new; their parent directory
must exist.

```sh
python3 tools/review_sheet.py export csv kit/review-sheet/source.csv kit/review-sheet/selection.json /fresh/review
```

The selection is explicit:

```json
{"key_columns":["id"],"edit_columns":["status","name"]}
```

Export creates a private directory with `manifest.json` and `editable.csv` (or
`editable.tsv` for TSV). Edit only the selected non-key cells in `editable.csv`.
Keep every row and column, preserving each key exactly. Save UTF-8 using the same
delimiter. If using a spreadsheet app, import all columns as text so IDs such as
`001`, dates and formula-looking strings are not automatically changed. Ordinary
CSV has no type metadata to force another app to follow that instruction.

For the synthetic example only, `kit/review-sheet/edited.csv` shows completed
edits, with both rows and columns reordered. Copy it over the exported
`/fresh/review/editable.csv` to reproduce the example, or edit that file manually.
The real original is never the edit destination.

```sh
python3 tools/review_sheet.py propose kit/review-sheet/source.csv /fresh/review /fresh/proposal
```

`propose` reads the edited sheet, compares by exact key and freezes its inputs into
a second private directory. It contains:

- `corrections.json`: the existing typed MoonLeaf recipe, with exact keys and
  before/after text values. Review this file before applying.
- `edited-sheet.txt`: the exact edited CSV/TSV snapshot, stored under a fixed name.
- `manifest.json`: the source identity and selected edit scope.
- `plan.json`: source, canonical manifest, edited-sheet, recipe and intended-copy
  digests, changed row/cell counts and limitations.

The summary on stdout contains counts, digests, editable column names and
limitations, without cell values. The example changes four cells in three rows.
No-op sheets produce a clear refusal and no proposal directory. Changing the
working sheet after proposal creation does not change this frozen proposal;
create another proposal to capture additional edits.

```sh
python3 tools/review_sheet.py apply kit/review-sheet/source.csv /fresh/proposal /fresh/corrected.csv
```

Apply recomputes the proposal from the retained source and frozen edited sheet,
checks all stored results and the correction recipe, then creates a new full-table
copy. It independently reads back the actual destination with the standard-library
CSV reader, compares every cell, and checks the original bytes again. Its receipt
includes source, edited-sheet, recipe and copy digests, changed counts,
`text_values_reopened: true`, and `render_verified: false`.

Directories are created with mode 0700 and files with mode 0600, subject to a more
restrictive umask. The plan, exported sheet, source and recipes can contain private
information. The output retains unselected source columns. Do not assume that
limiting the review sheet also removes those columns from the final copy; inspect
and authorize any sharing separately.

## Matching and correction semantics

- Select 1–32 key columns and at least one editable column by exact header name.
  Keys and editable columns must be disjoint. Names are distinct, nonempty and at
  most 4,096 UTF-16 units. The source has 1–128 distinct nonempty headers.
- Every row has a globally unique key tuple. Key components are nonempty text up
  to 4,096 UTF-16 units. There is no trimming, case folding, Unicode normalization,
  numeric coercion or delimiter-based tuple concatenation.
- All selected columns and all keys must remain in the edited sheet. Row and
  column reordering is allowed. Missing, added, duplicate or changed keys fail
  with a diagnostic. Adding/deleting rows and changing the selected column set
  are not part of this workflow. Restore the sheet or export a new one.
- A key is the identity chosen by the caller. Swapping existing keys between
  records looks like value changes assigned to those keys; the tool cannot infer
  a reviewer's intent. Review each key and before/after pair before application.
- Only changed cells appear in the recipe, ordered by original source row and
  then the selection's editable-column order. Blank-to-text and text-to-blank
  changes are supported; blanks are typed text `""`, not typed Empty/null.
- Every value stays text. A numeric-looking `001` or `12.50` keeps its spelling.
  Quotes, Unicode, embedded commas/tabs and line breaks are preserved as values.
  Output uses fully quoted fields and CRLF records; original quoting, BOM and
  line-ending bytes are not preserved. No formatting or formula calculation occurs.
- The full copy preserves source header/row order, stable keys, and every
  unselected or unchanged cell. Source bytes are never intentionally rewritten.

## Source identity, conflicts and authority

Source digests bind this workflow to the original bytes. If that file changes
between export, proposal and application, export a new sheet against the newer
source and review again. If you retained the original snapshot and frozen proposal,
[review them against the newer source](REBASE_REVIEW_EDITS.md) to carry selected
corrections forward with explicit conflict choices. Ordinary apply still refuses
source drift; the separate workflow produces a new current-bound proposal.

The manifest, sheet, plan and hashes are unauthenticated local material. They do
not prove who edited a sheet, whether a person approved it, or whether a chosen
scope was authorized. A person who rewrites the whole bundle can produce another
internally consistent proposal. Hosts own trusted original/selection retention,
review, file access, external concurrency, destinations and sharing authority.

Existing destinations are refused and never overwritten. Failed I/O can leave
an incomplete private directory; use a new one after diagnosing the issue. Failed
copy readback leaves the destination for diagnosis without a success receipt;
retry to a fresh destination. There is no cleanup, automatic overwrite or delivery
side effect. Checks detect observed source changes but are not filesystem locks.

CSV/TSV formula-looking strings are literal text here but may execute in external
spreadsheet apps. This tool neither sanitizes formulas nor makes those apps safe.
No reviewer identity, approval, signature, print readiness, delivery or customer
acceptance status is asserted.

## Existing product integration

The generated `corrections.json` has only `key_columns` and `edits`, each with an
exact key, column and typed text `before`/`after`. It targets the unchanged
`jsontable.parse_correction_recipe`, `Table.correct` and `cmd/correct` interfaces.
A host with an existing compiled MoonLeaf build can consume it directly:

```sh
node /existing/build/cmd/correct/correct.js csv ORIGINAL.csv /fresh/proposal/corrections.json report json
node /existing/build/cmd/correct/correct.js csv ORIGINAL.csv /fresh/proposal/corrections.json copy xlsx
```

Use `tsv` in that position for TSV input. These commands write the existing report
or copy to stdout. The caller must retain/check the original digest and manage a
fresh destination; shell redirection can truncate files before the CLI starts.
The Python `apply` lane instead uses its existing bounded delimited parser and
copy/readback boundary and never launches a compiler or external application.

This adds a human-editable round trip to existing manual typed corrections,
read-only reconciliation and policy-driven pseudonymization. It does not add
another comparison report or automatic anonymization policy.

## Bounds and evidence

Regular input files are at most 8 MiB. Each delimited source, edited sheet and
copy must fit 2,097,152 UTF-16 units, 10,000 total rows including header, and
100,000 cells. Malformed quoting and ragged rows fail through the existing parser.
The correction recipe contains 1–1,000 changed cells and at most 1,048,576 UTF-16
units. Unchanged cells do not count against that edit limit. Files are read into
memory; this is a small reviewed-export workflow, with no performance or hostile
input SLA.

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests -p review_sheet_test.py -v
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests -p pseudonymize_test.py -v
```

R480 adds 11 focused Python tests. They exercise real export/propose/apply CLI
processes, independent CSV readback and a separate simple recipe consumer,
reordered review rows/columns, exact composite IDs, Unicode TSV, empty/multiline
values, unchanged private columns, source conflicts, frozen proposals, destination
conflicts, failed-readback retry and the actual changed-cell budget. The six
synthetic kit files reproduce the complete value transformation. The 12 existing
pseudonymization checks cover the reused parser and host boundary.

These tests do not execute the full MoonBit correction command or document-session
API, native/browser/Office UI, rendering, XLSX output or MoonDesk/MoonProj linkage.
The published recipe shape is source-inspected and independently consumed in
Python; this round makes no new compiled-core compatibility claim. PRD W04/B08
and W06/R02 motivate literal delimited editing and a reviewable fresh copy, while
B12 leaves host authority explicit. The full reviewed-client-copy journey remains
unqualified. R50 is the last fully verified cumulative baseline; R51–55 remain
separate.

## Review selected records instead of the whole table

Use [review batches](REVIEW_BATCHES.md) when a reviewer needs only explicit
stable-key records and read-only context. The new `batch-export` and
`batch-propose` commands return to the ordinary proposal and `apply` contract.
Only the exported batch is record-scoped; the resulting proposal and copy retain
full-source records and must not be shared as a record-scoped extract.
