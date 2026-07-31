# WP02 OPC security problem/fix ledger

## Relationship target traversal above package root

- **Status:** Fixed
- **Severity:** High
- **Affected inputs:** Internal relationship targets with more parent segments than the source directory can satisfy.
- **Symptom:** A target such as `../../secret.xml` from `word/document.xml` normalized to `secret.xml`, silently retargeting the relationship.
- **Root cause:** Normalization discarded unmatched `..` segments.
- **Fix:** Preserve unmatched parents and reject relationship resolutions equal to `..` or beginning with `../`; valid leading-parent normalization remains supported.
- **Verification:** Focused tests cover above-root rejection and `../media/image.png` normalization; required project checks pass.
- **Preservation impact:** Public names and valid-input behavior are unchanged; malformed traversal now uses the existing `PackageError` path.
- **Residual risk:** URI escaping and non-path URI semantics are outside this slice.
- **Follow-up:** Review relationship URI decoding separately; do not combine it with CRC/content-types work.

## Duplicate relationship identifiers

- **Status:** Fixed
- **Severity:** Medium
- **Affected inputs:** Relationships XML containing repeated `Relationship` `Id` values.
- **Symptom:** Duplicate identifiers were accepted, creating ambiguous references.
- **Root cause:** Required attributes were checked, but identifier uniqueness was not.
- **Fix:** Reject a repeated `Id` while parsing a relationships part.
- **Verification:** A focused package-level test asserts `InvalidPackage` for duplicate `rId1`; required project checks pass.
- **Preservation impact:** Valid documents and public APIs remain unchanged; only invalid duplicates are rejected.
- **Residual risk:** Duplicate detection is linear in relationship count.
- **Follow-up:** Consider an internal set only if profiling warrants it.

## Controller verification repair

- **Status:** Fixed after reproduced failed validation
- **Failed attempt evidence:** Controller validation found two exact blockers: the duplicate-ID test catch handled only `InvalidPackage`, and `moon info` left an extra blank line at EOF in seven generated interface files, causing `git diff --check` failures.
- **Root cause:** The test's `catch` was non-exhaustive even though it asserted the intended duplicate-ID error; generated `.mbti` output had two trailing newlines rather than one after interface regeneration.
- **Fix:** Add an explicit fallback catch that fails on any unexpected package error while retaining the exact `duplicate relationship Id: rId1` assertion. Normalize `docx/pkg.generated.mbti`, `opc/pkg.generated.mbti`, root `pkg.generated.mbti`, `pptx/pkg.generated.mbti`, `scene/pkg.generated.mbti`, `xlsx/pkg.generated.mbti`, and `xml/pkg.generated.mbti` to one terminal newline after formatting/interface generation.
- **API impact:** None beyond the intended OPC additions; this repair changes only test exhaustiveness, generated-file EOF whitespace, and this ledger.
- **Verification:** Re-run `moon check --target all --warn-list +73`, `moon test --target all`, and `git diff --check`; warning 73 diagnostics are accepted, but errors are not.

## Duplicate-ID fixture parser repair

- **Status:** Fixed after reproduced failed validation
- **Failed-attempt evidence:** Controller validation passed all-target checking (with the existing accepted warning 73 diagnostics) and `git diff --check`, but `duplicate relationship Id is rejected` failed on every target with `invalid relationships XML` before duplicate detection.
- **Root cause:** The fixture used self-closing `Relationship` elements, a form this XML parser grammar does not accept reliably across targets.
- **Fix:** Keep both `rId1` entries and their required attributes unchanged, but express each `Relationship` with an explicit closing tag so the fixture is valid for this parser and reaches the duplicate-ID check.
- **API impact:** None; only the test fixture and this ledger changed.
- **Verification:** `moon fmt`; no `moon info` is needed because no API changed; `moon check --target all --warn-list +73`; `moon test --target all` expecting 23/23 on every target; and `git diff --check`.

## Repeated-fixture self-closing syntax repair

- **Failure:** The duplicate-relationship fixture stopped at XML parsing because both self-closing tags used unsupported whitespace before `/>`.
- **Fix:** Changed both tags from ` />` to `/>`, allowing the test to reach `PackageError InvalidPackage("duplicate relationship Id: rId1")`.

## Duplicate relationship-ID regression

- **Reproduced root cause:** the relationships XML itself was not the failure. Using the
  same parser-proven shape as `pptx/pptx_test.mbt` (plain `Relationships`, immediate
  `/>`) parses successfully. The broad raising `try ... catch ... noraise` in
  `parse_relationships` remained active while relationship validation ran, so the
  intentional duplicate-ID `PackageError` was caught and replaced with `invalid
  relationships XML`.
- **Fix:** scope XML-error translation to the `@xml.parse(text)` expression only. Keep
  duplicate-ID validation outside that catch, preserving `duplicate relationship Id:
  rId1`. The OPC regression fixture now reuses the known-passing plain
  `Relationships` shape without `xmlns`.
