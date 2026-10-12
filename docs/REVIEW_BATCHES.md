# Review only assigned records with read-only context

An operator can now prepare a small review batch for explicit records from a
larger CSV/TSV export. Reviewers see the exact stable keys, explanatory context
such as a customer or product name, and the columns they may change. They do not
need the other records or internal fields to correct their assignment.

This extends the existing `tools/review_sheet.py` host workflow with
`batch-export` and `batch-propose`. Ordinary review-sheet export selects columns
but includes every row and has no read-only context columns. A batch selects
rows as well. Returned edits become an ordinary source-bound proposal, so the
existing accept/reject, merge, rebase and verified-copy operations work without
new application semantics.

## Complete local example

Run from the repository root with Python 3. No dependencies or Moon compilation
are required. Use fresh paths for every output directory and final copy.

```sh
python3 -B tools/review_sheet.py batch-export csv \
  docs/samples/review-batches/source.csv \
  docs/samples/review-batches/selection.json /fresh/path/assigned-review
```

The selection is explicit; no filter language or numeric key coercion is used:

```json
{
  "key_columns": ["id"],
  "edit_columns": ["status"],
  "context_columns": ["name"],
  "row_keys": [["003"], ["001"]]
}
```

`assigned-review/manifest.json` describes the retained source digest, selection,
selected/source row counts and limits. `assigned-review/editable.csv` contains:

```csv
"id","name","status"
"001","Ada","pending"
"003","Chen","open"
```

Export order follows source order, regardless of the key-selection order.
Only those records and those columns appear as cell values in the export.
The manifest includes selected keys and source metadata, including the total
row count and digest, but no unselected record values. Inspect both files and
obtain any required permission before sharing. This command does not send them.

The reviewer edits only `status`. Keep `id` and `name` unchanged. Row and column
reordering is allowed, as demonstrated by the checked-in `reviewed.csv`:

```sh
# In this synthetic demonstration, replace the editable sheet with reviewed data.
cp docs/samples/review-batches/reviewed.csv /fresh/path/assigned-review/editable.csv
python3 -B tools/review_sheet.py batch-propose \
  docs/samples/review-batches/source.csv /fresh/path/assigned-review \
  /fresh/path/private-proposal
```

Inspect `private-proposal/corrections.json` and `plan.json`. The proposal has
exact text changes for `001/status` and `003/status`, retains the entire source
identity and uses the existing `moonleaf.review-sheet-plan.v1` format. It freezes
the reviewed batch and ordinary full-row working data, so subsequent edits to
the original batch do not change this proposal.

```sh
python3 -B tools/review_sheet.py apply \
  docs/samples/review-batches/source.csv /fresh/path/private-proposal \
  /fresh/path/corrected.csv
```

The full copy retains row `002`, every internal note, source row order and all
unselected columns. Its cell values match `expected-copy.csv`. Original source
bytes stay unchanged. The existing receipt confirms text-value readback and
explicitly leaves rendering unverified.

**The private proposal and full copy are not scoped reviewer exports.** The
proposal's `edited-sheet.txt` includes all source rows for the selected key/edit
columns, and the final copy includes every source field. Do not send either as
though it contained only the assigned records. Export a separate reviewed batch
for another assignment.

## Continue through established operations

- Use [accept/reject selection](SELECT_REVIEW_EDITS.md) on the ordinary proposal
  to keep only chosen proposed cells. Context never becomes a correction.
- Make two batches with different `row_keys` and convert each to a proposal
  against the same retained source. Use [merge](MERGE_REVIEW_EDITS.md) to combine
  their disjoint changes, or resolve overlapping conflicting edits explicitly.
- If the export changed while people reviewed, prepare against the retained
  original, then [rebase](REBASE_REVIEW_EDITS.md) onto the current export. Ordinary
  rebase compares edited cells; context is frozen for the original review, not a
  promise that the current context still matches. Inspect new context separately
  if it affects whether a correction remains appropriate.

## Exact contract and recovery

The selection object requires exactly four fields. `key_columns` contains
1–32 distinct existing columns, `edit_columns` 1–128, and `context_columns` zero
or more distinct existing columns. Use `[]` when no context is needed. The three
column groups must be disjoint. Combined width is limited by the source's
128-column maximum. Key and column-name text is limited to 4,096 UTF-16 units.

`row_keys` contains 1–9,999 distinct arrays, one nonempty text value for each
ordered key column. Keys must exist exactly in the source; `001` and `1` remain
different. Source keys must be globally unique, including unselected records.
No keys are inferred from row position, and adding/removing records is excluded.

On import, keep exactly the exported headers and selected key set. Reordering
is allowed. Changing a context value refuses the whole batch, even if other
edits are valid; restore context and retry. Empty replacement text, quoted
commas, tabs, newlines and Unicode remain literal text. An unchanged batch
requires no copy and creates no empty proposal.

The manifest is recomputed against the exact source snapshot and selection.
Any source-byte drift refuses preparation. Keep the original to prepare a
proposal for rebase, or export a new batch from the new source. Existing proposal
application still independently recomputes the full plan/recipe and checks
source identity. `batch.json`, `batch-manifest.json` and `edited-batch.txt` are
retained provenance for human inspection, not authentication or extra apply
permissions; the existing apply step consumes the ordinary proposal files.

Regular inputs and manifest files are at most 8 MiB. The reused delimited parser
limits tables to 2,097,152 UTF-16 units, 10,000 rows including the header and
100,000 cells. Exported batches must reopen within those same bounds. The final
ordinary proposal retains its 1,000-changed-cell and 1,048,576-UTF-16-unit recipe
limits. Scope the assignment or reduce the changed cells if those are exceeded.

Directories use mode 0700 and files 0600, subject to a stricter umask. Existing
paths are never overwritten. Failed writes may leave partial private evidence;
retain it for diagnosis and retry to fresh paths. Snapshot rechecks do not
provide filesystem locking or authenticated reviewer identity.

## Evidence and boundaries

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests -p 'review*_test.py' -v
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests -p 'pseudonymize_test.py' -v
```

R556 adds focused Python functional cases for real CLI export/propose/apply,
absence of unselected source values in exported files, immutable context with
recovery, exact composite keys, reordered Unicode/multiline TSV, frozen
proposals, independent recipe consumption and CSV readback, merge/selection/
rebase continuation, change budgets and the checked-in example.

MOONLEAF-W04/B08 motivate bounded literal corrections with meaningful reopen
checks. W06/R02 motivate inspectable changes and retained originals; B12 leaves
permissions, review, destinations and sharing with the host. Assigned-record
review removes the need to reveal a whole dataset or permit editing explanatory
context merely to collect a small correction. It does not complete the full
MoonDesk-to-MoonProj reviewed-client-copy journey.

No type inference, formula calculation, rendering, Office application, native
build, document-session, MoonDesk/MoonProj linkage or provider/hardware execution
is qualified by these tests. Formula-looking strings may execute in an external
spreadsheet app. Local hashes and review files do not establish authorization,
customer acceptance, delivery or payment. R50 remains the last fully verified
cumulative baseline; R51–55 remain separate.
