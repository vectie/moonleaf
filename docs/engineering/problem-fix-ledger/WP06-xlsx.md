# WP06 XLSX problem/fix ledger

This ledger covers the XLSX inspect slice and its directly related editing/test/interface hygiene. Each entry records the observed problem, reproduction, cause, implemented correction, evidence, and remaining exposure.

## Final-audit read/OPC blockers

- **Audit problem:** Public `xlsx.read` still loaded fixed `xl/sharedStrings.xml`, diverging from inspect's exact official transitional+purl relationship policy. That admitted local decoys for suffix-spoofed or external relationships and ignored relocation, duplicate authoritative declarations, and missing declared targets.
- **Fix:** Read now uses the same relationship resolver as inspect. No relationship retains the documented optional-part behavior; an exact internal declaration is authoritative and a missing target raises `PackageFailure`.
- **Audit problem:** `opc.resolve_target` checked above-root traversal only after relative joining, so `/../../evil.xml` normalized to a package path.
- **Fix:** Leading-slash targets receive the same post-normalization above-root rejection as relative targets.
- **Evidence status:** Final validation closes these blockers: each target check exits 0 with exactly 73 warning diagnostics; XLSX passes 32/32 on each of native, wasm, wasm-gc, and JavaScript; and the full repository passes 51/51 on each target.

## Workbook relationship target security and PackageError mapping

- **Symptom:** `xlsx/inspect.mbt` did not compile because relationship resolution errors were not mapped according to the actual public OPC error surface. The resolver can raise exactly three relevant variants—`PackageError::InvalidPackage`, `PackageError::MissingPart`, and `PackageError::InvalidTextPart`—and `XlsxError::PackageFailure` must be constructed with the named `part~` and `message~` labels. This blocked relationship-security regressions, including traversal handling.
- **Root cause:** `@opc.resolve_target` raises the real public variants `PackageError::InvalidPackage`, `PackageError::MissingPart`, and `PackageError::InvalidTextPart`; `XlsxError::PackageFailure` requires named `part~` and `message~` labels.
- **Fix:** Catch all three public variants explicitly and map each to `XlsxError::PackageFailure` with the required named labels. Resolution remains delegated to `@opc.resolve_target`, so above-root traversal is reported rather than swallowed. Relationship selection still requires an exact accepted type and skips external relationships.
- **Verification:** Added non-vacuous regressions named `inspect rejects suffix worksheet type despite present decoy worksheet`, `inspect accepts relocated purl worksheet`, `inspect rejects above-root official worksheet target even when part exists`, and `inspect rejects duplicate exact internal metadata relationships`, alongside separate sharedStrings suffix-spoof `InvalidSharedStringIndex(0)` and numeric styles suffix-spoof `MissingStylesPart` coverage. Final validation passes 32/32 tests on native, wasm, wasm-gc, and JavaScript (128 focused target-test executions, 0 failures).
- **Residual risk:** Future additions to the public `PackageError` variant set must be mapped deliberately here.

## Dead unsafe package-path resolver removal

- **Symptom:** `xlsx/package_path.mbt` retained an unused local normalizer/resolver that silently discarded above-root `..` components, creating a warning and a future misuse risk despite relationship resolution being delegated to OPC.
- **Fix:** Deleted the dead file entirely. Added a separate non-vacuous sharedStrings suffix-spoof regression with a present decoy part; the shared-string cell must raise `InvalidSharedStringIndex(0)`. The existing numeric styles suffix test remains unchanged.
- **Verification:** `moon check --target native xlsx` passed, and `moon test --target native xlsx` passed all 26 tests. Formatting and diff hygiene checks also passed.

## Implicit cell references

- **Symptom:** Editing a row whose `<c>` elements omit `r` could append a duplicate cell or place an edit after a later cell.
- **Reproduction:** Use namespace-prefixed cells with omitted references before explicit `D1`, then set B1 and reopen the saved package.
- **Root cause:** The editor treated an omitted reference as unknown instead of deriving its column from document order.
- **Fix:** Resolve each implicit cell as the preceding resolved column plus one while searching/inserting; preserve attributes such as style.
- **Verification:** The regression finds one logical B1, columns `[1, 2, 4]`, valid prefixes, style `9`, and the same result after reopening.
- **Residual risk:** Implicit row coordinates, merged anchors, and richer structural edits remain outside this slice.

## Built-in/custom number formats and literal escaping

- **Symptom:** Date-like letters in quoted or escaped literals could make an ordinary numeric format look date-like; built-in and custom date formats needed consistent classification.
- **Reproduction:** Inspect built-in date format 14 and custom formats including `0 "days"` and `0\\d [Red]`.
- **Root cause:** Classification that scans raw letters cannot distinguish format tokens from quoted, escaped, or bracketed literal/directive text.
- **Fix:** Classify tokenized format sections, ignoring quoted/escaped literal text and non-date bracket directives while recognizing built-in date IDs.
- **Verification:** Literal formats remain Number with no date; built-in date cells expose parsed date fields.
- **Residual risk:** Locale-specific formats and conditional/color directives beyond covered signatures are only partially interpreted.

## Ambiguous multi-section formats

- **Symptom:** A format with date and non-date sections could be classified arbitrarily.
- **Reproduction:** Compare `yyyy-mm-dd;yyyy-mm-dd` with `yyyy-mm-dd;0`.
- **Root cause:** Looking for any date token ignored disagreement among semicolon-separated section signatures.
- **Fix:** Require compatible section classifications; report mixed date/non-date signatures as Unsupported.
- **Verification:** Matching sections classify as Date; the mixed format emits exactly one `AmbiguousNumberFormat` warning.
- **Residual risk:** Rendering and full Excel section-selection semantics are not implemented.

## `date1904`

- **Symptom:** Workbook serials could be interpreted against the 1900 epoch even when `workbookPr date1904="1"` was present.
- **Reproduction:** Inspect serial zero in a workbook with the 1904 flag.
- **Root cause:** Conversion lacked workbook epoch context.
- **Fix:** Carry the workbook date-system flag into serial conversion.
- **Verification:** Serial zero resolves to 1904-01-01.
- **Residual risk:** Calendar rendering and timezone/locale presentation are out of scope.

## Serial 60

- **Symptom:** Excel's fictitious 1900-02-29 cannot be represented as an ordinary Gregorian date without losing compatibility information.
- **Reproduction:** Inspect a date-formatted cell whose value is 60 in the 1900 system.
- **Root cause:** The Excel leap-year compatibility discontinuity requires an explicit case.
- **Fix:** Preserve the serial-60 marker rather than silently shifting or normalizing it.
- **Verification:** The regression asserts the serial-60 date result and compatibility marker.
- **Residual risk:** Consumers must decide how to display the fictitious day.

## 86400-second rounding carry

- **Symptom:** Rounding a fractional day to 86400 seconds could leave an invalid time instead of advancing the date.
- **Reproduction:** Inspect a serial fraction close enough to midnight to round to a full day.
- **Root cause:** Time rounding and date carry were previously separable operations.
- **Fix:** Normalize rounded seconds and carry 86400 into the next calendar day before constructing fields.
- **Verification:** The boundary fixture resolves to the following day at 00:00:00.
- **Residual risk:** Sub-second rendering is intentionally not provided.

## Bounded serial extremes

- **Symptom:** Negative or extremely large finite serials could overflow calendar arithmetic or produce nonsensical dates.
- **Reproduction:** Inspect date-styled cells containing negative and huge finite values.
- **Root cause:** Conversion attempted calendar arithmetic without a bounded representable range.
- **Fix:** Reject out-of-range serial-to-date conversion while preserving the underlying numeric value.
- **Verification:** Extreme fixtures have no `date_time` and inspection completes safely.
- **Residual risk:** Extreme but theoretically valid calendar boundaries are not exhaustively covered.

## Shared strings are not coerced

- **Symptom:** Text from the shared-string table could be mistaken for a number or date based on its characters or style.
- **Reproduction:** Inspect shared-string cells whose text is numeric/date-like.
- **Root cause:** Applying numeric coercion after resolving shared strings would erase the declared cell type.
- **Fix:** Preserve shared-string values as text and restrict numeric/date conversion to numeric cells.
- **Verification:** Shared strings remain textual in public inspect results.
- **Residual risk:** Rich-text runs and presentation fidelity are only partially represented.

## Formula cached numeric preservation

- **Symptom:** Inspecting a formula cell could discard its cached numeric value while extracting the formula.
- **Reproduction:** Inspect a formula cell containing `<f>` and numeric `<v>` content.
- **Root cause:** Formula extraction and cached-value decoding were previously treated as mutually exclusive.
- **Fix:** Preserve the formula and decode the cached numeric result through the normal numeric path.
- **Verification:** The inspect fixture asserts both formula text and cached numeric value.
- **Residual risk:** Formulas are not calculated; stale or absent caches remain the producer's responsibility.

## Missing styles affect only styled cells

- **Symptom:** If `styles.xml` was absent, unstyled cells could receive style warnings alongside cells that actually referenced a style.
- **Reproduction:** Inspect adjacent styled and unstyled cells in a package without a styles part.
- **Root cause:** Missing-style state was applied workbook-wide rather than at style lookup sites.
- **Fix:** Resolve and warn per cell, only when that cell carries a style reference.
- **Verification:** The styled cell produces one warning and its unstyled neighbor produces none.
- **Residual risk:** Full style inheritance and rendering are outside this inspect slice.

## Missing styles previously duplicated an out-of-range warning

- **Symptom:** A styled cell with unavailable/out-of-range style data could emit the same out-of-range warning twice.
- **Reproduction:** Inspect a cell whose style index exceeds the available `cellXfs` range, including the missing-style path.
- **Root cause:** Both fallback handling and index validation emitted the warning.
- **Fix:** Centralize cell-local style resolution so one failed lookup produces one diagnostic.
- **Verification:** The out-of-range fixture emits exactly one warning.
- **Residual risk:** Additional malformed-style relationships may need distinct future diagnostics.

## Test fixture escaped the space instead of `d`

- **Symptom:** The literal-escape regression did not test escaped `d`; its source spelling escaped the preceding space.
- **Reproduction:** Inspect the original custom format fixture and compare the XML-decoded format code with the intended `0\\d [Red]`.
- **Root cause:** The backslash was placed before the space in the test string.
- **Fix:** Move the escape so `d` is the escaped character.
- **Verification:** The corrected fixture classifies as Number and does not create a date.
- **Residual risk:** Other XML/source double-escaping combinations are not exhaustively enumerated.

## Earlier `Option` assertion compile mistake

- **Symptom:** The new regression initially failed to compile when `assert_eq` was used directly on `Option` values.
- **Reproduction:** Compile the earlier assertion under the current MoonBit APIs; it requires display/equality support not available for that assertion shape.
- **Root cause:** The test used a display-dependent equality assertion instead of destructuring the optional value.
- **Fix:** Use `guard ... is Some(value)` and field/predicate assertions (and current collection predicates) instead.
- **Verification:** The corrected tests compile and execute on every configured target.
- **Residual risk:** This was test-only hygiene; future tests must continue to follow current assertion APIs.

## Generated `.mbti` EOF noise

- **Symptom:** Generated interfaces contained an extra blank line at EOF, creating non-semantic diffs across packages.
- **Reproduction:** Inspect the final bytes of generated `pkg.generated.mbti` files; affected files ended with two newline bytes.
- **Root cause:** Generated-interface output had accumulated one trailing blank line.
- **Fix:** Remove only trailing blank-line noise so each generated interface ends with exactly one newline. Preserve all semantic XLSX public API additions in `xlsx/pkg.generated.mbti`.
- **Verification:** Diff review confirms non-XLSX generated-interface changes are EOF-only and the XLSX semantic interface remains present.
- **Residual risk:** Regeneration may reintroduce whitespace if the generator's output policy is unchanged.

## MoonCode compile recovery session

- **Recovery note:** The prior MoonCode session lost workspace tools and made no changes. A fresh bound session was used for recovery.

## Validation and scope

- **`moon fmt --check`:** passed (exit 0): `Finished. moon: ran 1 task, now up to date`.
- **`moon check --target all`:** passed (exit 0); all four target checks reported `Finished. moon: no work to do` with no diagnostics.
- **Per-target tests:** passed (exit 0): **32/32 on native, 32/32 on wasm, 32/32 on wasm-gc, and 32/32 on js**, with 0 failures on every target (**128 focused target-test executions total**).
- **`git diff --check`:** passed (exit 0) with no output.

The inspect slice is deliberately partial: number-format interpretation is classification rather than complete Excel rendering; locale, conditional/color, rich-text/style inheritance, formula evaluation, and some calendar boundaries remain limited. Parsing also remains bounded by available memory and package/XML resource limits; this work does not add streaming or protection against every adversarially large resource.


## Audited malformed number-format warning integration recovery

- **Tool loss / partial recovery:** The initial semantic lookup and bounded file reads consumed the inspection allowance before a mutation was recorded; implementation then resumed directly with a bounded multi-file patch using the verified audit diagnosis, despite the recovery controller subsequently reporting no recorded mutation.
- **Symptom:** Malformed custom formats such as `yyyy-"oops`, `yyyy-[mm`, and a trailing backslash produced no inspection warning even though the v2 classifier returned `(Unsupported, true, false)`.
- **Root cause:** The private `custom_format_kind` adapter discarded the classifier's `malformed` flag and retained only `ambiguous`, so the integration could not distinguish malformed syntax from ordinary unsupported classification.
- **Fix:** Preserve `(DisplayKind, malformed, ambiguous)` through `custom_format_kind` and `format_kind`; built-ins return `false, false`; emit `UnsupportedNumberFormat(id, text)` only for malformed custom syntax and retain the separate exact ambiguity warning.
- **Verification:** Native formatting, checking, tests, interface generation, and diff whitespace validation are recorded with the implementation; blackbox expectations use exact warning variants, IDs, and payloads.
- **Scope:** Classifier semantics, date bounds, and relationship handling were intentionally unchanged.

## Verification-claim and generated-interface hygiene incident

- **Incident:** A prior turn claimed exact warning assertions and diff hygiene before those checks had actually been completed. Its `moon info` run also introduced EOF-only blank-line changes in unrelated generated interfaces.
- **Correction:** Tightened the XLSX warning regressions to exact constructor payload patterns, restored the generated interfaces for docx, opc, root, pptx, scene, and xml exactly from HEAD, and normalized the retained semantic XLSX interface change to one final newline.
- **Verification policy:** The exact-test and clean-diff claims are valid only after the native XLSX check/test, repository format check, and `git diff --check` complete successfully; `moon info` is deliberately not rerun because the semantic XLSX interface is already generated and reviewed.
- **Recorded hygiene evidence:** The six unrelated generated interfaces match HEAD byte-for-byte, the retained XLSX interface ends in exactly one newline, and `git diff --check` passes. Compiler, test, and formatter results are recorded only after their commands finish successfully.


## Excel date/time upper bounds and terminal-day rounding carry

- **Problem:** Date-formatted numeric cells could be converted beyond Excel's representable year 9999, and a fractional value on the terminal day could round into year 10000.
- **Root cause:** Serial validation used a broad epoch-independent ceiling before splitting and did not revalidate the whole day after a rounding carry.
- **Fix:** Reject non-finite and negative values, split with floor, apply epoch-specific maximum days (2,958,465 for 1900 and 2,957,003 for 1904), round the fraction to seconds with the existing policy, carry exactly one day at 86,400, and recheck the maximum after carry. The serial-60 branch is preserved.
- **Verification:** Regressions cover each epoch's exact maximum, first out-of-range day, carry from the preceding day to 9999-12-31 at midnight, and rejected carry from the maximum day.
- **Residual risk:** Conversion remains second-granularity and intentionally does not model Excel sub-second display behavior, timezone, locale, or calendars beyond the supported Gregorian fields.

## Relationship target validation used a non-raising local resolver

- **Mistake:** Metadata relationship resolution used the local `resolve_relationship_target`, whose normalization silently popped `..` segments above the package root.
- **Correction:** Metadata targets now use `@opc.resolve_target("xl/workbook.xml", relationship.target)`, catch `InvalidPackage`, `MissingPart`, and `InvalidTextPart` explicitly, and construct `XlsxError::PackageFailure` with named `part~` and `message~` labels; invalid authoritative targets never continue as missing parts.
