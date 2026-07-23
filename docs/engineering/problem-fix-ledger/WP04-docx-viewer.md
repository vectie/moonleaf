Status: Implemented

# WP04 DOCX viewer problem/fix ledger

Current verification evidence: **37/37 tests pass on each of wasm, wasm-gc, JavaScript, and native** (148 target-test executions).

## DOCX-001 — Style cascade precedence
- **Symptom:** Effective run formatting could ignore inherited styles or apply sources in the wrong order.
- **Reproduction:** Inspect paragraphs combining document defaults, paragraph-style run properties, character styles, and direct run formatting.
- **Root cause:** Formatting sources were not represented as one ordered OOXML cascade.
- **Fix:** Resolve `docDefaults`, inherited paragraph style, paragraph-style run properties, inherited character style, and direct run properties in increasing precedence; direct formatting wins.
- **Verification:** Focused style tests cover defaults, `basedOn`, paragraph/character precedence, missing parents, and cycles; 37/37 pass on all four targets.
- **Residual risk:** OOXML style semantics remain partial, including linked styles, theme/font resolution, and conditional table styles.

## DOCX-002 — Default paragraph style omission
- **Symptom:** A paragraph without `w:pStyle` skipped the style marked as the default paragraph style.
- **Reproduction:** Inspect a style sheet with a default paragraph style and a paragraph having no explicit style ID.
- **Root cause:** Style lookup began only from an explicit paragraph style reference.
- **Fix:** Select the declared default paragraph style when `w:pStyle` is absent, then apply it over document defaults.
- **Verification:** `inspect_document applies default paragraph style over docDefaults` passes on all targets.
- **Residual risk:** Multiple malformed defaults and unsupported style categories use conservative fallback behavior.

## DOCX-003 — Signed page margins and malformed numeric fallback
- **Symptom:** Valid negative top/bottom page margins were lost, while malformed numeric attributes could be treated as meaningful values.
- **Reproduction:** Inspect `w:pgMar` with negative `w:top`/`w:bottom`, and malformed numeric margin attributes.
- **Root cause:** Page margins shared parsing assumptions with nonnegative dimensions and lacked consistent parse-failure fallback.
- **Fix:** Parse top/bottom margins as signed integers and represent malformed numbers as absent; retain appropriate nonnegative constraints elsewhere.
- **Verification:** Focused structure regression covers signed and malformed values; 37/37 pass on all targets.
- **Residual risk:** Unit conversion and the broader section/page model remain partial OOXML implementations.

## DOCX-004 — Table gridSpan validation
- **Symptom:** Zero, negative, or malformed `w:gridSpan` values could produce invalid cell metadata.
- **Reproduction:** Inspect table cells containing invalid or malformed `w:gridSpan` values.
- **Root cause:** Raw numeric parsing was accepted without enforcing the positive-span invariant.
- **Fix:** Accept only positive spans and fall back to the default span of one for invalid input.
- **Verification:** Focused table structure tests pass on all targets.
- **Residual risk:** Full merged-cell geometry, table layout, and conditional styling are not rendered.

## DOCX-005 — Relationship parse failures
- **Symptom:** Malformed document relationships could be silently conflated with an empty relationship set.
- **Reproduction:** Supply a malformed document relationship part to `inspect_document`.
- **Root cause:** Relationship parsing failure was not surfaced distinctly in inspection diagnostics.
- **Fix:** Preserve the document inspection result while recording a stable warning for malformed relationship XML.
- **Verification:** `inspect_document reports malformed document relationships` passes on all targets.
- **Residual risk:** Relationship and URI semantics are partial; hostile package sizes still require caller-enforced resource bounds.

## DOCX-006 — External, missing, and invalid image targets
- **Symptom:** Image relationships with external, missing, or invalid internal targets could be misclassified or disappear without useful diagnostics.
- **Reproduction:** Inspect image relationships targeting an external URI, an absent package part, or a rejected package-relative path.
- **Root cause:** Relationship classification, target resolution, and package-part existence checks were not handled as separate outcomes.
- **Fix:** Record external image metadata without resolving a media part; warn for missing parts and rejected internal targets; retain successfully resolved media locations.
- **Verification:** Focused relationship/resource regression covers retained and rejected targets; 37/37 pass on all targets.
- **Residual risk:** URI normalization is intentionally limited, and embedded image bytes are not decoded or rendered.

## DOCX-007 — Invalid-target scene-warning duplication
- **Symptom:** An invalid image target produced both its resolution warning and a misleading `DOCX_IMAGE_SCENE_UNSUPPORTED` warning.
- **Reproduction:** Inspect an image relationship whose internal target cannot be validly resolved.
- **Root cause:** The scene warning was emitted from relationship discovery rather than successful image resolution.
- **Fix:** Emit the unsupported-scene warning only for successfully resolved images.
- **Verification:** The relationship regression asserts warning behavior and passes on all targets.
- **Residual risk:** Successfully resolved images still cannot be projected because the shared text scene has no image primitive.

## DOCX-008 — Brittle/deprecated test representation
- **Symptom:** Earlier tests depended on deprecated inspection expectations and quote-sensitive debug text, causing failures unrelated to behavior.
- **Reproduction:** Run the earlier assertions against current typed inspection results and warning formatting.
- **Root cause:** Tests compared unstable rendered representations instead of semantic values.
- **Fix:** Compare typed `Option` values and stable warning codes with `assert_eq`.
- **Verification:** The recovered focused tests contribute to 37/37 passing on every target.
- **Residual risk:** Debug-format snapshots should continue to be avoided unless formatting itself is the contract.

## DOCX-009 — Generated `.mbti` EOF noise
- **Symptom:** `moon info` added a blank line at EOF to generated interfaces, creating unrelated diffs and `git diff --check` failures.
- **Reproduction:** Generate interfaces and inspect trailing bytes or run `git diff --check`.
- **Root cause:** The interface generator emits an additional terminal newline relative to repository formatting.
- **Fix:** Remove only the extra blank line at EOF from generated `.mbti` files while preserving all semantic additions in `docx/pkg.generated.mbti`.
- **Verification:** `git diff --check` is part of final verification; the DOCX interface still exposes `inspect_document` and its public metadata types.
- **Residual risk:** A later `moon info` invocation may recreate the whitespace noise and require the same hygiene normalization.

## Remaining limits

The DOCX viewer does not decode or render embedded images. OOXML semantics are partial, including styles, tables, sections, relationships, numbering, themes, and layout. Parsing and inspection do not yet expose comprehensive configurable limits for input size, XML depth, node count, relationship count, or decoded resource size; callers must apply resource bounds to untrusted documents.

## Final independent DOCX audit repairs

- Missing `word/_rels/document.xml.rels` is now treated as zero relationships; malformed existing relationship XML alone emits `DOCX_RELATIONSHIPS_INVALID`.
- Header, footer, and image relationship types now use exact transitional/strict OOXML URI allowlists, blocking suffix-spoof relationship types.
- Real-structure regressions cover negative/malformed section margins and zero, negative, and malformed `gridSpan` values, including fallback to 1 and `DOCX_GRID_SPAN_INVALID`.
- Exact external image relationships retain a resource with `media_part=None`, emit one external warning, and do not emit a scene-unsupported warning.
- Verification: 37 tests per target across four targets, 148 target-test executions.
