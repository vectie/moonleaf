# Accept some reviewed cell edits and reject others

A reviewer may propose several corrections while the deliverable author wants
only some of them in the client copy. Export one decision row per proposed cell,
mark each `accept` or `reject`, then freeze the accepted subset as a new ordinary
MoonLeaf review-sheet proposal. The existing apply command reopens a fresh full
table copy. Rejected cells retain their original values, including when another
cell in the same row is accepted. Unselected/private columns remain in the copy.

This is a local selection of exact proposals. Choices do not authenticate an
approver, grant permission, record customer acceptance or manage collaboration.

## Reproduce the complete workflow

Run from a MoonLeaf checkout with Python 3.10+, using only the standard library.
Replace `/fresh` with an existing directory. Every output directory or copy must
be new. The source and samples are synthetic.

```sh
python3 tools/review_sheet.py export csv kit/review-sheet/source.csv kit/review-sheet/selection.json /fresh/review
cp kit/review-sheet/edited.csv /fresh/review/editable.csv
python3 tools/review_sheet.py propose kit/review-sheet/source.csv /fresh/review /fresh/proposal
python3 tools/review_selection.py export kit/review-sheet/source.csv /fresh/proposal /fresh/choices
```

Open `/fresh/choices/decisions.csv` in a text editor or import every column as text
in a spreadsheet. Each row contains `change_id`, `key_json`, `column`, `before`,
`after`, and a blank `decision`. Inspect the exact key and before/after pair, then
enter exactly `accept` or `reject` for every change. Blank choices cannot proceed.
All identity/value columns must stay exactly as exported; row and column
reordering is allowed. To propose a different value, edit the original review
sheet and create a new proposal and decision sheet instead.

For the synthetic example, use the committed decision sheet, which accepts the
name change for ID `001` and status change for ID `003`, while rejecting both
other proposed status changes:

```sh
cp kit/review-selection/decisions.csv /fresh/choices/decisions.csv
python3 tools/review_selection.py select kit/review-sheet/source.csv /fresh/proposal /fresh/choices /fresh/selected
python3 tools/review_sheet.py apply kit/review-sheet/source.csv /fresh/selected /fresh/selected-copy.csv
```

The selected directory contains the existing `manifest.json`, `edited-sheet.txt`,
`corrections.json`, and `plan.json`. It can be opened by the unchanged
`review_sheet.py apply` command. `corrections.json` retains the exact existing
MoonLeaf typed-text recipe shape; there is no new apply format. The accepted
changes retain parent order. Accepting every cell produces the original recipe
and copy values. Rejected proposed values do not enter the copy.

Two additional local records, `selection.json` and the frozen `decisions.csv`,
retain the parent proposal digest, decision-sheet digest, selected recipe digest
and counts/choices. Later edits to the working decisions do not alter the frozen
selected proposal. The apply command verifies its existing proposal inputs and
recipe, not these extra annotation records. The annotations are unauthenticated
history, not an approval gate or authoritative audit trail.

If all changes are rejected, select succeeds with
`all_rejected_no_copy_needed`. The new directory contains only the decision
records; no correction recipe, proposal or copy is created. Keep the original.
Do not run apply on this no-change result. Correcting pending or invalid choices
can be retried; an existing destination is never overwritten.

## Boundaries and recovery

- The full source and frozen parent proposal are recomputed with the same
  `prepare_proposal` boundary used by existing apply. Source drift or changed
  proposal contents require a new review; saved choices cannot retarget a new
  proposal merely because change numbers look similar. A frozen selected proposal
  can separately enter [three-way review against a newer source](REBASE_REVIEW_EDITS.md);
  only its accepted cells are considered, with new explicit conflict choices.
- Every proposed change must appear exactly once with its original exact key,
  column and before/after text. Decision-sheet rows are not matched by position.
  Keys are not normalized, trimmed or coerced.
- CSV is always the decision-sheet format, even for TSV sources. Its quoted
  fields preserve Unicode, tabs, embedded line breaks, empty values and quotes.
  A selected TSV proposal still applies to a TSV full copy.
- The existing parent limits apply: 1–1,000 proposed cell edits, bounded UTF-8
  files and bounded delimited tables. The decision sheet itself must fit the
  existing parser: at most 2,097,152 UTF-16 units and 100,000 cells. Large repeated
  keys/values can exceed this limit even if the source proposal fits; export
  refuses rather than publishing a sheet it cannot reopen.
- New directories use 0700 and files 0600, subject to a stricter umask. Failed
  I/O may leave an incomplete directory for diagnosis; retry to a fresh one.
  Original, proposal and decision inputs are never intentionally rewritten.
  Digest checks are observations, not filesystem locks or signatures.
- Keys, before-values, rejected values and user choices remain in the private
  selection records. Final copies retain unselected source columns. Inspect
  separately before sharing any file; this command does not deliver it.
- CSV formula-looking strings remain literal in this tool but can execute in
  external spreadsheet software. No spreadsheet sanitization, type inference,
  formula calculation, formatting or rendering is performed.

## Product rationale and evidence

MOONLEAF-W06/R02 require an inspectable intended change and retained original;
W04/B08 require supported delimited round trips, while B12 leaves authority with
the host. The previous review-sheet workflow transformed every proposed change.
This adds a deliberate accept/reject step without rewriting a JSON recipe or
manually undoing a reviewer's other suggestions.

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests -p 'review_selection_test.py' -v
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests -p 'review_sheet_test.py' -v
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests -p 'pseudonymize_test.py' -v
```

Nine focused tests exercise actual export/select/apply CLI processes, independent
CSV readback, accept-all/reject-all, same-row mixed choices, reordered choices,
frozen selection reuse, changed input recovery, fresh-destination retry, and
literal multiline TSV values with composite keys. Existing review-sheet and
pseudonymization tests cover the unchanged application/parser boundary.

This qualifies the bounded Python host adapter and text-value copy readback.
No MoonBit command, document-session API, native app, browser, Office renderer,
XLSX output, MoonDesk linkage or full reviewed-client-copy journey was run.
Recipe compatibility is the existing source-inspected format, not a newly
executed compiled-core claim. R50 remains the last fully verified cumulative
baseline; R51–55 remain separate.
