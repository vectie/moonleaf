# Correct workbook text in one verified copy

Inspect exact existing text cells, put the intended corrections in a JSON recipe,
and apply them together to a fresh XLSX copy. One stale or unsupported target
refuses the entire request before any output file is created. A successful report
includes both byte digests and the existing workbook-content comparison, so the
reviewer can see the exact supported before/after values.

This supplies the missing practical XLSX correction workflow for PRD W02, B05,
B06 and W06. It uses the existing conservative editor and verified session, with
an additive atomic text-only API. There is no approval/sign-off state and the
host retains authority over files, destinations, sharing and delivery.

## Inspect, describe, apply

Use the retained `hustcer/fzip@0.8.5` graph and pinned MoonBit toolchain. Every
Moon invocation must use an absolute external target directory.

```sh
moon --target-dir /absolute/build build cmd/xlsx-edit --target js --frozen --strip -j 1
node /absolute/build/js/debug/build/cmd/xlsx-edit/xlsx-edit.js inspect kit/xlsx-edit/contacts.xlsx Customers B2 B3 E2
node /absolute/build/js/debug/build/cmd/xlsx-edit/xlsx-edit.js inspect kit/xlsx-edit/contacts.xlsx 'Private notes' A1
node /absolute/build/js/debug/build/cmd/xlsx-edit/xlsx-edit.js apply kit/xlsx-edit/contacts.xlsx kit/xlsx-edit/corrections.json /fresh/client-copy.xlsx
```

`inspect SOURCE.xlsx SHEET ADDRESS [ADDRESS ...]` accepts 1 to 100 exact uppercase
canonical A1 addresses in one exact, case-sensitive sheet. It returns source
SHA-256 and `{sheet,address,text,style_id}` targets under
`moonleaf.xlsx-text-targets.v1`. All inspected targets must be supported; a single
refusal returns no partial target list. It does not discover used ranges or
invent cells. Use an existing preview or workbook to choose coordinates.
Hidden sheets are included when explicitly named; hidden/filtered rows are not
excluded. A style ID is an uninterpreted existing identifier, not a visual claim.

`apply SOURCE.xlsx REQUEST.json FRESH_COPY.xlsx` requires precisely these top-level
fields and exactly four string fields for each edit:

```json
{
  "version": 1,
  "source_sha256": "SHA-256 returned by inspect",
  "edits": [
    {"sheet":"Customers","address":"B2","expected":"Ada","replacement":"Ada Lovelace"},
    {"sheet":"Private notes","address":"A1","expected":"Private draft","replacement":"Ready for review"}
  ]
}
```

There must be 1 to 100 distinct sheet/address pairs. All expected values refer to
the original read snapshot. Repeated targets are errors, not sequential edits.
No-op entries still validate identity, text and support. An all-no-op batch keeps
the session revision and original package payloads; save may normalize ZIP bytes.
Duplicate JSON properties have the existing JSON parser's last-value behavior;
provide unique property names. Unknown fields, nonstring replacements, stale
source hashes and stale expected values are refused.

All validation and edits complete in memory, then the normal session save reopens
and rerenders the copy and checks its package payloads. The adapter rechecks each
corrected target and produces the [bounded content comparison](COMPARE_WORKBOOKS.md).
It exclusively creates a mode-0600 destination with `wx`, reads it back and
compares the bytes before printing a success report. Existing files, directories,
source paths, hardlinks and symlinks cannot be overwritten. A failed write or
readback can leave an unverified fresh file; it is never deleted or overwritten.
Inspect that failure and retry to another fresh destination. No success receipt
is emitted for a failed copy. The source is only opened for reading.

The report `moonleaf.xlsx-text-copy.v1` has `source_sha256`, `copy_sha256`, the
complete request, requested/changed cell counts, `comparison`, reopen/readback
results, warnings and session diagnostics. Keep it with the original and copy.
The source is read as a snapshot, without a filesystem lock; the digest refers
to those exact bytes, not proof that its path did not later change. Digests do
not establish authorship, truth, approval, delivery or customer acceptance.

## Supported text and preservation

- Existing ordinary inline-string or shared-string cells only. A shared-string
  correction becomes a new inline string; other cells sharing its source string
  remain unchanged. Shared-string parts are not modified or compacted.
- A selected string must be exactly one plain `t`, with optional `xml:space`.
  Rich runs, phonetic annotations, unknown selected cell children/metadata,
  alternative namespace layouts and SpreadsheetML `_xHHHH_` escape tokens are
  refused. Standard default transitional SpreadsheetML namespace is required.
- Text is exact: no trimming, number/Boolean/date conversion or formula inference.
  `001`, empty strings, Unicode, tabs, CR and LF are retained. Worksheet edits
  encode CR as `&#13;` so XML newline normalization preserves standalone CR and
  CRLF in independent readers; literal `&#13;` text stays literal. A replacement such
  as `=SUM(1,2)` is stored as literal inline text, never as a formula.
- Numeric, Boolean, error, missing cells and formula cells are refused. A merge
  intersection (including its anchor) or any formula result range intersecting
  the target also refuses the request. Rich text is not silently flattened.
- Existing cell style attributes are preserved. Non-target worksheet XML is
  retained semantically by the existing XML serializer, not byte-for-byte.
  Untouched OPC part payloads are retained byte-for-byte. ZIP compression,
  attribute spelling/order and selected shared-string representation may change.
- Formula expressions and stored caches are preserved, not recalculated. Changes
  to text precedents can make dependent results stale. Reopen does not establish
  calculation freshness; tables, charts and pivot caches are not refreshed.
- The existing archive and comparison bounds remain in force. Ambiguous sheet
  names, aliased worksheet parts, coordinates and selected payloads are refused.
  This is not general OOXML namespace/schema validation or a malicious-document
  sandbox. External relationships are not fetched and no macros are executed.
- No Office layout fidelity, print readiness, signatures, advanced editing,
  complete package semantic equivalence or MoonDesk UI acceptance is established.

## Library and limits

```mbt nocheck
let target = @xlsx.inspect_text_cell(archive, sheet_name="Customers", address="B2")
let changed = session.correct_xlsx_text_cells([
  { sheet: "Customers", address: "B2", expected: target.text, replacement: "Ada Lovelace" },
])
let verified = changed.save_as_copy()
```

`@xlsx.correct_text_cells(archive, edits)` is the package-level API; it returns a
new package after validating the whole request. The session wrapper commits the
batch as one revision. Neither API accesses a filesystem or binds a SHA-256 by
itself; the caller must apply an OPC open policy and bind the source identity.
Existing cell editor/session interfaces are unchanged. Worksheet editing now
preserves decoded CR as character references during serialization.

Each expected/source or replacement string is limited to 32767 UTF-16 units;
expected-plus-replacement text totals at most 1000000 units per batch. XML-invalid
characters and unpaired surrogates are refused. The CLI uses an 8 MiB source and
1 MiB JSON request cap, 8 MiB per archive entry and 16 MiB total expanded content.
Its comparison preflight adds 100 sheets, 100000 explicit cells, 10000 merges and
4000000 compared text units. Upstream XML/OPC bounds can refuse an input sooner.
Everything is in memory; no streaming or performance SLA is claimed.

## Retained evidence

`kit/xlsx-edit/contacts.xlsx` is an actual XlsxWriter 3.2.9 workbook, with styled
shared strings, repeated values, rich text, hidden sheet, merges, array formulas
and explicit synthetic caches. Its producer sets a fixed creation timestamp;
provenance and a four-cell corrections recipe are committed. Tests consume the
retained bytes without installing or regenerating dependencies.

`tests/xlsx_edit_cli.py EXTERNAL_BUILD FRESH_EVIDENCE_DIRECTORY` executes the real
Node adapter, independently reopens with openpyxl 3.1.5 and compares ZIP/XML
payloads. It checks source/copy hashes, typed literal text, styles, unchanged
formulas and caches, unrelated parts and untargeted sheet XML, independent CRLF/CR/literal-entity round trips, unsupported and
stale requests, destination conflicts, injected readback failure and a fresh
retry. Focused MoonBit tests exercise the additive library/session APIs on JS and
native. These are new focused results, not recovered historical qualification.
