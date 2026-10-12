# Carry a reviewed correction onto a newer CSV/TSV source

An offline review can finish after the source export has changed. Previously,
MoonLeaf required starting the review again. This workflow compares a frozen
[review-sheet proposal](REVIEW_SHEETS.md) with a newer retained snapshot, exposes
three-way cell conflicts, then builds an ordinary proposal against the **current**
source. The existing apply command still checks the exact current digest and
writes a new, reopened full-table copy.

This is useful when a support lead has reviewed names and statuses while someone
else updated internal notes, added records or corrected the same status. Only
proposed cells are considered for carrying forward. Every other current value,
current row order and current column order stays intact. You must retain the
original snapshot used by the parent proposal; the newer source does not replace
that evidence.

## Complete local-file example

Use Python 3.10+ from this checkout. Only the standard library is needed. Replace
`/fresh` with an existing parent directory; every generated directory and final
copy below must be new. All committed samples are synthetic.

First reproduce a frozen proposal against the original source:

```sh
python3 tools/review_sheet.py export csv kit/review-sheet/source.csv kit/review-sheet/selection.json /fresh/sheet
cp kit/review-sheet/edited.csv /fresh/sheet/editable.csv
python3 tools/review_sheet.py propose kit/review-sheet/source.csv /fresh/sheet /fresh/proposal
```

Then inspect it against the newer snapshot:

```sh
python3 tools/review_rebase.py export kit/review-sheet/source.csv /fresh/proposal kit/review-rebase/current.csv /fresh/rebase-review
```

The private review directory contains `manifest.json` and `decisions.csv`. The
manifest binds both source digests, the parent plan/recipe digests and the current
selection manifest. The CSV lists each proposed cell's exact key, column,
original value, reviewed value, current value, status and decision:

- `ready`: current still equals original. Default decision is `use-reviewed`.
- `already_applied`: current already equals the proposed value. Default is
  `keep-current`; it does not generate another correction.
- `conflict`: current differs from both original and reviewed. Decision is blank.
- `missing_row`: the proposed exact key is absent in current. Decision is blank;
  the current value field is empty because there is no row, not because the cell
  contains empty text. Only `keep-current` is permitted, retaining its absence.

Inspect every row. Change only `decision` to exactly `keep-current` or
`use-reviewed`. All blanks must be resolved. You can choose `keep-current` for a
ready edit too. `use-reviewed` on a present conflict deliberately replaces the
current value; compare all three values before choosing it. Row and column
reordering of this decision sheet is allowed. Changing a key, status, value or
column, removing a row, or adding a different change is refused.

For this synthetic example, the committed choices replace the conflicting status
for `001`, carry its name correction, keep the already-empty status of `002`, and
leave deleted record `003` absent:

```sh
cp kit/review-rebase/decisions.csv /fresh/rebase-review/decisions.csv
python3 tools/review_rebase.py prepare kit/review-sheet/source.csv /fresh/proposal kit/review-rebase/current.csv /fresh/rebase-review /fresh/rebased-proposal
python3 tools/review_sheet.py apply kit/review-rebase/current.csv /fresh/rebased-proposal /fresh/copy.csv
```

The result matches `kit/review-rebase/expected-copy.csv` by cell values. It retains
new record `004`, the newer private notes and the extra current column. Only two
cells change. The conflicting status's correction recipe says `before: awaiting`
and `after: approved`, rather than using the old `pending` value. The final copy
is verified against the actual current source through the unchanged apply lane.

## Proposed changes and evidence

The prepared directory contains the same `manifest.json`, `edited-sheet.txt`,
`corrections.json` and `plan.json` consumed by `review_sheet.py apply`. No apply
format or old-source mismatch override is introduced. The rebased recipe is
ordered by current source rows, then editable-column selection order.

`rebase.json` and the frozen `decisions.csv` additionally retain both snapshot
identities, parent identity, choices, classification counts and rebased-recipe
digest. Later edits of the working decision sheet cannot change the prepared
proposal. These extra records are unauthenticated local annotations. Existing
apply checks its normal proposal inputs, not these two annotation files. They do
not constitute signatures, approval gates or an authoritative audit trail.

If every proposed value is already present, all choices retain current, or every
missing row is kept absent, preparation returns `no_changes_no_copy_needed`.
Only the two annotation files are written. There is no proposal or client copy;
keep the current source and do not run apply on that result.

A parent proposal may itself come from [selective acceptance](SELECT_REVIEW_EDITS.md).
Only its accepted cells are considered. Rejected original suggestions cannot
reappear through this workflow. To propose a different new value, export a new
ordinary review sheet against current rather than editing evidence columns.

## Source identity, schema and recovery

- Both snapshots use the original proposal's delimiter and literal UTF-8 text
  semantics. The current source must still contain every selected key/edit
  column. Other current columns may be added, removed or reordered; their
  current values are preserved, with no inference about schema meaning.
- The original source and frozen parent proposal are recomputed through the same
  boundary used by existing apply. The original digest must still match. A
  missing old snapshot cannot be reconstructed from a scoped edited sheet.
- Current keys must be unique and nonempty. Exact composite keys have no trimming,
  case folding, numeric coercion or Unicode normalization. Changed keys appear
  as removed plus added records. Nothing guesses identity or restores removed
  rows; a reused key can refer to a different real entity, so key suitability is
  the host's responsibility.
- Current rows absent from the old snapshot and untouched current cells remain
  intact. This is cell-level carry-forward, not complete-row keep-first/last
  consolidation, a two-way reconciliation report, or a background collaboration
  system. It does not add/delete rows or merge arbitrary files.
- If current or parent changes after review export, preparation refuses. Export a
  new rebase review and resolve it against that snapshot. If current changes
  after preparation, ordinary apply refuses before writing a copy. A stale
  decision sheet is never automatically retargeted.
- Existing output paths are refused. Pending choices and validation failures
  create no destination. Failed I/O can leave an incomplete private directory
  for diagnosis; retry to a fresh destination. Files use 0600 and directories
  0700, subject to a stricter umask. Sources are read-only, not locked: digest
  checks observe changes and do not prevent external concurrent mutation.

## Bounds, privacy and qualification

The existing bounds apply: regular files up to 8 MiB; delimited tables up to
2,097,152 UTF-16 units, 10,000 total rows, 100,000 cells and 128 headers; at most
1,000 corrections and 1,048,576 UTF-16 recipe units. The decision CSV repeats
original, reviewed and current values and must also fit those table bounds.
Export checks it can reopen before creating a review directory. All files are
processed in memory; no streaming or performance SLA is asserted.

The review CSV is always comma-delimited, even for TSV source/copy files. Values
remain literal text, including `001`, empty strings, quotes, tabs, Unicode and
embedded newlines. Output quoting and line endings may differ from input. No
formula recalculation, number inference, formatting, type conversion or rendering
occurs. Formula-looking CSV/TSV strings can execute in external spreadsheet
applications; import as text or use a text editor for review.

Sources, review sheets, proposals and annotations contain private values. The
final copy retains all current columns. Review scope is not redaction and none of
these commands sends or shares files. Hosts retain authority over access, user
choices, destinations, concurrent edits, sharing and delivery acceptance.

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests -p 'review*_test.py' -v
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests -p 'pseudonymize_test.py' -v
```

R518 adds 12 focused tests: actual CSV and TSV CLI processes, independent CSV
readback and a separate simple recipe consumer, all four classifications,
explicit conflict recovery, deleted rows, current schema and row reordering,
selected parent proposals, no-op outcomes, drift refusal/review retry, frozen
proposal behavior and fresh-destination recovery. This qualifies the bounded
Python adapter and text-value copy readback. It does not execute MoonBit, native
or browser UIs, document-session APIs, rendering, XLSX output or MoonDesk/MoonProj
integration. Compiled-core compatibility is not newly claimed. R50 remains the
last fully verified cumulative baseline; R51–55 remain separate.

PRD MOONLEAF-W04/B08 motivate exact delimited copies; W06/R02 call for retained
originals and an inspectable intended client-copy change; B12 leaves conflicts
and authority with the host. This makes one formerly blocked stale-review
workflow usable without weakening exact-source application. It is not the full
host-level reviewed-client-copy release gate.
