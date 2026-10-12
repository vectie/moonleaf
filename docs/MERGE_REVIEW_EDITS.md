# Combine independently reviewed CSV/TSV corrections

Two people may review different columns of the same retained export. Previously,
applying one proposal made the other proposal's source identity stale, while
picking one complete row discarded the other person's cell edits. This local
workflow combines the exact proposed cells, deduplicates agreement and exposes
conflicting proposed values before creating one ordinary MoonLeaf proposal.
Use the unchanged [review-sheet apply](REVIEW_SHEETS.md) command to create and
read back the final full-table copy.

This is local file reconciliation, without live collaboration or authenticated
reviewer identity. Both frozen proposals must refer to exactly the same source
bytes, input format and ordered key columns. If one was made against a different
source version, resolve that version difference separately with
[review rebase](REBASE_REVIEW_EDITS.md), retain its original evidence and then
combine two proposals bound to the same snapshot. Do not silently substitute a
new source or change a parent's manifest.

## Reproduce a complete synthetic example

Use Python 3.10+ and its standard library. Run from the repository root. Replace
`/fresh` with an existing private parent directory. Every output directory and
copy below must be new. The committed example contains invented records.

The first reviewer edits names and statuses. The second edits statuses and
regions. Their proposals agree on Ada's approved status, disagree about Bo's
status, and make separate name and region changes.

```sh
python3 tools/review_sheet.py export csv kit/review-merge/source.csv kit/review-merge/left-selection.json /fresh/left-sheet
cp kit/review-merge/left-edited.csv /fresh/left-sheet/editable.csv
python3 tools/review_sheet.py propose kit/review-merge/source.csv /fresh/left-sheet /fresh/left
python3 tools/review_sheet.py export csv kit/review-merge/source.csv kit/review-merge/right-selection.json /fresh/right-sheet
cp kit/review-merge/right-edited.csv /fresh/right-sheet/editable.csv
python3 tools/review_sheet.py propose kit/review-merge/source.csv /fresh/right-sheet /fresh/right
python3 tools/review_merge.py export kit/review-merge/source.csv /fresh/left /fresh/right /fresh/merge-review
```

Inspect `/fresh/merge-review/decisions.csv`. It contains each changed cell once,
with its key, column, original text, both proposed values, separate presence
flags, classification and decision. Presence flags distinguish an intentionally
proposed blank from a side that did not propose any change:

- `left_only`: use `left` by default
- `right_only`: use `right` by default
- `agreed`: both propose exactly the same text; use `left` by default, once
- `conflict`: the proposed texts disagree; the decision is blank

Only true conflicts require a fresh choice. Inspect all rows and change only
`decision` to exactly `left`, `right` or `original`. A selected side must have a
proposal for that cell. `original` retains the source text and can reject any
change, including an agreed or one-sided edit. Every blank must be resolved.
New text cannot be typed into this sheet; propose it using a new review sheet.

For the example only, the committed decisions choose the right-hand `held` value
for Bo and keep the other defaults. Reproduce that explicit choice, freeze the
merge, and make the copy:

```sh
cp kit/review-merge/decisions.csv /fresh/merge-review/decisions.csv
python3 tools/review_merge.py prepare kit/review-merge/source.csv /fresh/left /fresh/right /fresh/merge-review /fresh/merged
python3 tools/review_sheet.py apply kit/review-merge/source.csv /fresh/merged /fresh/copy.csv
```

The resulting values match `kit/review-merge/expected-copy.csv`: Ada's name is
`Ada, A.`, Ada's status is `approved`, Bo's status is `held`, and Chen's region
is `west`. All private columns and all source row/header order remain intact.
The source bytes stay unchanged. Stdout reports four changed cells and the
source/recipe/copy digests. It does not print cell contents.

The merged directory contains the usual `manifest.json`, `edited-sheet.txt`,
`corrections.json` and `plan.json`. It also retains `merge.json` and the frozen
`decisions.csv`, tying choices to the ordered left/right plan and recipe digests.
Keep the original source and both parent proposal directories with these files.
After preparation, changing the working decisions or either original editable
sheet does not change the frozen merged proposal. To revise it, prepare a new
merge review/proposal with a fresh destination.

You can pass the merged proposal to [selective review](SELECT_REVIEW_EDITS.md)
to accept/reject a subset before application, or use it as one parent of another
merge against the same source. There are exactly two parents per merge; this
workflow does not infer consensus, authority or precedence among reviewers.

## Matching, choices and recovery

Keys compare exact text tuples without trimming, number conversion or Unicode
normalization. The ordered key-column list must match across parents. Editable
column sets can differ; their union follows the source header order. Proposed
changes are emitted in source row order then source column order. Identical
parents are allowed and their edits appear once.

Decision rows and columns may be reordered. Keys, original/proposed values,
presence flags, classifications and change IDs must stay exact. Removing or
adding decisions is refused. Left/right identity is positional: swapping the
parents after export requires a new review. Each parent's complete frozen
proposal is recomputed through the existing review-sheet validation, so a
mismatched source or changed parent recipe is rejected before publishing output.

Choosing `original` for every changed cell creates only `merge.json` and the
frozen decisions, with `no_changes_no_copy_needed`; no correction proposal or
copy is created. To use a proposed value later, prepare another merge in a new
directory. If the source drifts before ordinary apply, it remains a source
conflict. Ordinary apply's existing destination refusal, recipe recomputation,
full-table text-value readback and unchanged-source check are not relaxed.

Regular source/input files are at most 8 MiB. The reused delimited parser limits
each table to 2,097,152 UTF-16 units, 10,000 rows including its header and 100,000
cells. There can be up to 2,000 distinct candidate edits across two 1,000-edit
parents, provided the decision sheet fits these bounds. The final proposal must
still have at most 1,000 changed cells and a recipe at most 1,048,576 UTF-16 units.
If the union exceeds that final budget, choose `original` for enough cells or
split the work deliberately into a separately reviewed workflow. Oversize
preparation fails before creating its output directory.

New directories use mode 0700 and files 0600, subject to a more restrictive umask.
Existing paths are never overwritten. Failed writes may leave partial private
outputs; retain them for diagnosis and retry to a fresh destination. Input
checks observe snapshots and do not implement filesystem locks.

## Limits and verification

All original/edited values, keys, recipes and review files may contain private
information. The final copy retains unselected source fields. Scope selection
is not redaction; inspect and authorize sharing separately. Hashes and local
choices do not authenticate reviewers or establish approval, delivery, customer
acceptance or payment. CSV/TSV formula-looking strings remain literal here but
may execute if opened by an external spreadsheet app.

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests -p 'review*_test.py' -v
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests -p 'pseudonymize_test.py' -v
```

R536 adds 12 focused Python cases: actual CLI export/merge/apply and independent
CSV/recipe consumption, disjoint scopes, shared agreement, all three conflict
choices, exact composite IDs and blank/Unicode/multiline TSV values, reordered
review rows/columns, frozen inputs, source mismatch, unchanged apply checks,
selective-review continuation and bounded union reduction. The synthetic recipe
reproduces the complete transformation.

MOONLEAF-W04/B08 and W06/R02 motivate reviewable literal edits and retained-source
copies. B12 leaves source retention, review, permissions, destinations and sharing
authority with the host. This Python host adapter does not execute MoonBit,
document sessions, rendering, Office applications, XLSX output or MoonDesk/
MoonProj linkage; the full reviewed-client-copy journey remains unqualified.
No dependencies, network or Moon commands are needed. R50 remains the last
fully verified cumulative baseline; R51–55 remain separate.
