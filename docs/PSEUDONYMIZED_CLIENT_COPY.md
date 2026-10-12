# Prepare a pseudonymized CSV/TSV client copy

Replace chosen customer/participant identity columns consistently without dropping
those columns or losing row correspondence. Repeated exact names receive the
same sequential token within that column; separate names receive different tokens.
Other selected columns can be masked to one literal string. This makes a useful
sample dataset for discussing repeated-customer patterns without including the
selected original names/email addresses in the client copy.

**This is pseudonymization, not anonymity or a security guarantee.** Unselected
columns, key values, free text, row order and relationships may still identify
people. Inspect the whole copy before sharing. Tokens are predictable, have no
cryptographic protection, reset for each file/column, and are not cross-file IDs.
This tool does not transmit files or grant permission to share them.

## Workflow

From a MoonLeaf checkout with Python 3.10 or newer, no external modules needed:

```sh
python3 tools/pseudonymize.py plan csv kit/pseudonymize/source.csv kit/pseudonymize/policy.json /fresh/private-plan
python3 tools/pseudonymize.py apply kit/pseudonymize/source.csv /fresh/private-plan /fresh/client-copy.csv
```

The example is entirely synthetic. Use `tsv` for tab-separated input. Plan creates
a new private directory (0700) containing `plan.json` and `corrections.json`
(0600). Existing directories are refused. Standard output summarizes affected
columns, target/changed cell counts, distinct token counts, source digest and
capability limitations; it does not contain original cell values.

Review that summary and the exact changes in `corrections.json` locally. The
recipe contains original values and keys, so it remains sensitive private
working material. Do not deliver the plan directory, recipe or original with a
client copy. Only the copy contains the pseudonymized/masked table; no token
mapping or before-values are embedded in it.

Apply explicitly receives the original, reviewed plan directory and fresh copy
path. It checks original bytes and recomputed policy/recipe/output digests,
refuses a changed source or plan, and never overwrites an existing destination.
The fresh copy is created with mode 0600. Its bytes are read back and parsed with
the independent Python standard-library CSV reader, checking the full intended
table, including header/row order and all unchanged cells. The original bytes
are re-read to detect changes during the operation. A successful JSON receipt
reports source/copy/recipe digests and `text_values_reopened: true`, with
`render_verified: false` and explicit limitations.

A failed readback leaves the destination for diagnosis, unverified. Retry to a
new destination after addressing the failure; the earlier file is not deleted
or overwritten. An incomplete private plan directory after an I/O failure is
also retained; create a new plan elsewhere. No success receipt is emitted on
failure. Hashes detect accidental changes; they are not signatures or proof of
an authorized reviewer. Review is the caller's decision, not a status the tool
can infer. A host remains responsible for access, review, destination selection,
sharing permission, external concurrency and delivery.

## Policy and exact semantics

```json
{
  "key_columns": ["record"],
  "columns": [
    {"column": "customer", "mode": "pseudonym", "prefix": "CLIENT-"},
    {"column": "email", "mode": "mask", "value": "[removed]"}
  ]
}
```

- Columns are addressed by exact header identity, never position, case folding
  or fuzzy matching. Unknown/repeated target columns and unknown fields fail.
- Keys use 1–32 distinct columns whose values form globally unique, nonempty
  text tuples. Leading zeros, Unicode, whitespace and component boundaries are
  preserved. Key columns cannot be transformed. Choose non-identifying row IDs
  where appropriate; unchanged keys may identify people.
- Pseudonyms assign `PREFIX0001`, `PREFIX0002`, etc. in first-occurrence order,
  independently per column. A prefix is 1–32 ASCII letters/digits/hyphens/
  underscores starting with a letter. There is no normalization: `Ada`, `ada`
  and `Ada ` are three distinct values. A later file with different row order
  may give the same source value a different token.
- Mask replaces every nonempty cell in that column with the exact `value`.
  The literal may be empty, but must be at most 32,768 UTF-16 units. It is not
  a regular expression. Empty source cells remain empty in both modes;
  whitespace-only cells are nonempty. A blank-only selection is refused because
  there is no cell-correction recipe to apply.
- All columns, rows and non-target values are retained. Numeric-looking values
  remain text. Embedded delimiters, quotes, tabs and line breaks survive as
  values. CSV/TSV output uses quoted fields and CRLF record separators; source
  quoting, BOM and line-ending bytes are not preserved. UTF-8 is required.
- Formula-looking strings in unselected columns or masks are preserved literally.
  External spreadsheet applications may execute them as formulas. This workflow
  is not a formula-sanitization tool or a safe spreadsheet execution environment.

## Existing MoonLeaf correction workflow integration

The private `corrections.json` is the existing strict
`parse_correction_recipe` / `Table.correct` / `cmd/correct` recipe, containing
only `key_columns` and typed `edits` with exact original `before` and generated
`after` text values. Each cell appears once; key columns are never edited.
The recipe includes nonempty target cells even if the replacement equals the
original; those report `unchanged` through the existing correction API.

A host already using the compiled MoonLeaf `cmd/correct` can use that recipe
without adopting the Python copy adapter:

```sh
node /existing/build/cmd/correct/correct.js csv ORIGINAL.csv /fresh/private-plan/corrections.json report json
node /existing/build/cmd/correct/correct.js csv ORIGINAL.csv /fresh/private-plan/corrections.json copy csv
```

Use `tsv` in the input-format position for TSV. The existing CLI emits its
existing CSV/JSON/XLSX forms to stdout; it does not implement the Python adapter's
source digest or exclusive destination checks. The host must perform those checks
and select safe fresh destinations. Shell redirection can truncate a file before
the CLI starts. Existing correction rules still apply; see
[typed table corrections](CORRECT_TABLES.md).

This adds policy-driven whole-column consistent token assignment and masking to
that correction workflow. Existing select/drop projection cannot preserve the
selected column's within-file relationships, and hand-authoring every exact cell
correction is unnecessary. The Python lane is an explicit file host adapter,
not a replacement implementation of the MoonBit document-session API.

## Bounds and evidence

Each regular input file is at most 8 MiB. The delimited source text is at most
2,097,152 UTF-16 units, with 1–128 unique nonempty headers, at most 10,000 total
rows including header, and 100,000 cells. Ragged rows and malformed quotes fail.
Key strings/names are at most 4,096 units. The generated recipe has 1–1,000 cell
edits and at most 1,048,576 UTF-16 units, matching the existing correction API;
this is a small reviewed-sample workflow, not bulk anonymization. Generated copies
must satisfy the same parser bounds. Whole files are held in memory; no hostile
input memory or performance guarantee is claimed.

Run the dependency-free workflow tests:

```sh
python3 -m unittest discover -s tests -p pseudonymize_test.py -v
```

R462: 12 Python tests exercise actual plan/apply subprocesses, repeated identities,
Unicode TSV/composite keys, private recipes, shape/quoting, key restrictions,
recipe edit bounds, source/plan changes, destination conflicts, failed readback,
retry and unchanged original bytes. The committed synthetic kit is reproducible.

A separate replay harness also copied exact unchanged `csv/csv.mbt`,
`scene/types.mbt`, `jsontable/lookup.mbt`, `jsontable/correct.mbt`, and the exact
`Table` declaration from `jsontable/table.mbt:5–8` into an isolated core-only
module. Two Moon JS tests consumed generated CSV and Unicode/composite-key TSV
recipes using the real parser and correction functions, matching every expected
cell and retaining the original. No ZIP/XLSX dependency was substituted. Source
hashes and harness logs are retained with the round evidence. This is focused
core compatibility evidence, not execution of the full MoonLeaf CLI/module,
MoonBit document sessions, native rendering, MoonDesk UI, Office fidelity,
print readiness or customer acceptance. PRD B08/W04 and R02/W06 motivate the
bounded copy workflow; the complete host/deliverable journey is still unqualified.
