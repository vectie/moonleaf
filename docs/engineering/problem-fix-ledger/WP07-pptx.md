# WP07 — PPTX viewer/simple editor problem/fix ledger

This ledger records the audited and verified PPTX slice. It claims neither a
public-API/product-behavior change beyond the fixes described here nor
originality or absence of third-party influence.

## Relationship validation and tests

Presentation slide and image relationships are accepted only when their type is
an exact strict or transitional OOXML relationship URI. Positive tests cover
both exact strict and exact transitional slide and image URIs. Negative tests
cover suffix-spoofed types, external targets, wrong types, unsafe above-root
targets, and missing relationships/parts.

The audit found that earlier strict-test claims were not backed by exact strict
positive fixtures; the tests were added and the claim corrected. Exact matching,
internal target mode, safe OPC resolution, and part existence are checked at the
resolution boundary.

## Image validation

A resolved image part is usable only when its effective `[Content_Types].xml`
content type is `image/*` and its bytes have a supported PNG, JPEG, or GIF
signature. Existing XML or other non-image package parts are rejected even when
a relationship points to them. The test fixture that had falsely been described
as a PNG is now a real minimal PNG. Tests cover exact strict/transitional image
relationships and invalid type, target, missing-part, content-type, and signature
cases.

## Transforms and flips

Transforms are read from the schema-local property container, avoiding accidental
descendant capture. Group horizontal/vertical flips affect computed child bounds
only; item-local flip is not represented in the scene model. The audit corrected
an earlier claim that flips were represented in scene items. Residual limitations
are explicit: transform arithmetic can overflow, group-coordinate division can
truncate, affine/rotation composition is incomplete, and some group resources or
unsupported content are intentionally omitted.

## Provenance and audit record

The audit found and fixed overstatements concerning a false PNG fixture,
provenance/originality and no-third-party assertions, strict positive-test
coverage, and flip representation. The exact PptxGenJS revision and files
consulted remain unknown; no claim is made about copied code, originality, or the
absence of third-party influence. The repository `NOTICE` carries the canonical
PptxGenJS MIT notice.

One attempted test record used an ambiguous record literal that did not compile;
it was replaced with an explicitly typed construction. A proposed unsafe bulk
rewrite was rejected in favor of narrow relationship, content-type, signature,
and transform changes. Remaining risks include transform overflow/truncation and
resource/content residuals noted above.

## Verification

The confirmed final run passed **32/32 tests on each of wasm, wasm-gc, js, and
native (128 executions total)**. Generator attribute verification and `git diff
--check` also passed. The 35 warning-73 diagnostics are pre-existing outside the
changed PPTX files.
