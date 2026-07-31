# Production hardening progress

This ledger records reproduced XML/OPC defects, fixes, verification, and remaining risks. It is intentionally evidence-based and should be updated with every hardening slice.

The prior broad milestone passed 93/93 tests on each of wasm, wasm-gc,
JavaScript, and native (372 executions). The current archive-policy slice uses
proportional verification: all-target check has zero errors; 12 focused OPC
tests plus one root-policy test pass on every target (52 executions); and
`moon info`, formatting, and diff checks pass. The broad format suite was not
repeated for this bounded change. `DocumentSession` root parity uses synthetic,
in-memory, minimally realistic/real-world-shaped DOCX, XLSX, and PPTX OOXML
packages, not checked-in real Office files; malformed root coverage is DOCX, so
this milestone does not claim cross-format malformed or warning-bearing unified
fixtures. Failed-edit tests verify byte equality as well as unchanged revision,
dirty state, scene, and diagnostics. Defensive-copy tests mutate nested scene
values, push an entry onto a returned diagnostics array, and mutate
`VerifiedDocumentCopy::bytes()`; they do not mutate nested diagnostic data; they
do not cover `@opc` `Package::part`, because `Package` and `Part` are public
mutable values.

WP06 XLSX relationship/type/OPC hardening is complete. Public `xlsx.read` now shares inspect's exact official transitional+purl relationship policy (external exclusion, relocation, duplicate-authority rejection, and declared-target failure), and OPC rejects both relative and leading-slash above-root traversal. Final matrix evidence is green: every native/wasm/wasm-gc/js check exits 0 with exactly 73 warning diagnostics; XLSX passes 32/32 per target (128 focused target-test executions); and the full repository passes 51/51 per target (204 full target-test executions). `moon info` recreated EOF-only blank lines in generated interfaces; after reviewing its semantic output, the six unrelated generated interfaces were restored to branch baseline and only the XLSX interface EOF blank line was removed. It was intentionally not rerun after that cleanup because it would recreate the known whitespace defect.

Prior checkpoint (not current HEAD): the controller merged the PPTX production-inspection work at commit `8276895`. Gates at that historical checkpoint reported 77 warnings and 79/79 tests per target (316 executions). Current source fixtures and synthetic in-memory rendering/editor-session coverage are present; current status is recorded below. Generated interface changes in that merge were EOF blank-line noise, with no semantic API change.

Archive security is now owned at the MoonLeaf boundary. Every public OPC,
viewer, and session open applies a validated per-open `ArchivePolicy`;
central-directory metadata is bounded before extraction; extraction enables
CRC verification; and actual entry count, names, and sizes must agree with the
preflight view. Hostile fixtures cover CRC corruption, counts, sizes, ratio,
depth, path length, traversal, aliases, duplicates, and exact-boundary success.
The dependency's coarser hard limits remain an additional ceiling. This does
not claim macro, signature, encryption, external-content, or semantic sandbox
safety.

Session dirty tracking is intentionally conservative. Semantic no-ops remain clean; text replacement returns `self` when `find == replacement` after capability/format validation and before low-level DOCX/PPTX editor dispatch, avoiding lexical XML rewrites for semantic identity. XLSX `replace_text` remains unsupported even when `find == replacement`. The PPTX regression proves entity-coded `A&#66;` renders `AB` while revision stays 0, state stays clean, the scene is unchanged, and saved slide XML bytes remain exact. Edit-away/edit-back remains dirty until save because undo and baseline-equivalence detection are not implemented.

## Problem/fix ledger

| Area | Symptom | Reproduction / evidence | Root cause | Fix | Verification | Residual risk |
|---|---|---|---|---|---|---|
| XML truncation and bounds | Truncated declarations, comments, CDATA, attributes, and elements must fail rather than return a partial tree; oversized or over-deep XML must stop at configured bounds. | Parser audit confirms explicit raising paths for terminators and closing tags, and integrated XML bounds provide configurable limits. | Streaming-by-offset parsing requires explicit delimiter handling plus bounded resource use. | Retain strict delimiter checks and implemented configurable limits. | Implementation evidence is integrated, and the final integrated check and test gates passed; expanded boundary/stress cases have not yet run. | Add black-box truncation cases and boundary/stress coverage at, below, and above each configured limit. |
| WP01 XML record compatibility | Native compilation failed when namespace expansion fields were added to legacy `Element`/`Attribute` construction and duplicate detection referenced unbound `aname`. | Native compiler reported incompatible-record, missing-field, and unbound-name errors. | Prefix-tolerant lexical QName work crossed the public legacy record boundary. | In `Parser::parse_element`, keep `Array[Attribute]`, compare `a.name == n`, push only `{ name: n, value: v }`, and return inferred legacy `{ name: qname, attributes: attrs, children }` records; rename the unused scope parameter to `_parent_scope`. No namespace fields are added and `parse_namespaced` remains unimplemented. | `moon fmt`; `moon check --target all`; `moon test --target all`: wasm 28/28, wasm-gc 28/28, js 28/28, native 28/28; `git diff --check`. | URI-aware parsing remains deferred to a separate `parse_namespaced` API; lexical namespace declarations are retained for round trips. |
| XML lexical local-name lookup and namespace limits | OOXML callers commonly bind arbitrary prefixes and must match schema local names, but namespace URI identity is not represented. | `Element::local_name`, `attribute`, and child lookup implement lexical local-name matching; URI-aware namespace identity is absent. | OOXML producers freely vary namespace prefixes, while the legacy XML model retains lexical QNames rather than expanded URI/local-name identities. | Retain prefix-tolerant lexical local-name lookup as the compatibility boundary; URI-aware namespace identity remains deferred. | Existing lexical local-name behavior is covered; broader prefixed/default namespace fixtures remain pending. | Same-local-name attributes or elements from different namespace URIs can be ambiguous until URI-aware parsing is implemented. |
| XML lexical content | Declarations/comments are discarded and CDATA is represented as text during parse/save. | Parser/serializer audit. | The current XML model stores elements, attributes, and text, not lexical trivia. | Preserve semantic text and safely escape it on serialization. | Pending entity/CDATA round-trip tests. | Exact lexical round-trip is unsupported and documented rather than falsely promised. DTD/entity declarations must remain unsupported for safety. |
| OPC ZIP paths | Absolute, parent, separator, encoded and whitespace aliases can escape or ambiguate a logical package namespace. | Policy preflight validates raw central-directory paths before extraction. | ZIP names are untrusted and normalization alone can hide traversal. | Reject non-canonical paths, excessive depth/length, and control/query/fragment forms before extraction. | Generated traversal, slash-alias, depth and length fixtures. | Unicode normalization equivalence is not claimed. |
| OPC duplicates | Two ZIP entries can identify the same logical part. | Policy preflight tracks normalized case-folded identities, including directory/file aliases. | ZIP permits duplicate names and slash/case variants. | Reject duplicate or aliased identities before extraction. | Exact duplicate and case-alias fixtures. | OPC lookup itself remains exact after the stricter open boundary. |
| OPC required metadata | A ZIP without `[Content_Types].xml` is not a valid OPC package. | Open/save explicitly reject its absence. | ZIP validity alone is insufficient for OPC validity. | Enforce the required content-types part at both boundaries. | Pending malformed-package fixture. | Content-type declarations themselves are not yet semantically validated. |
| OPC relationships | Internal relative targets must resolve against the source part; external targets must not be treated as package parts. | Relationship parser records `TargetMode`; the raising `resolve_target` API joins against the source directory and rejects above-package-root traversal for both relative and leading-slash targets. | Relationship targets are URI references, not ZIP-root paths by default. | Existing relative resolution and traversal rejection retained; URI fragment/query/percent-encoding canonicalization remains pending. | Synthetic DOCX, XLSX, and PPTX fixtures include root and nested part relationships; broader URI edge fixtures remain pending. | Full RFC 3986 canonicalization for fragments, queries, percent encoding, and other unimplemented URI semantics is not yet provided. |
| Save preservation | Unknown OOXML parts must survive load/edit/save byte-for-byte unless explicitly replaced. | `Package` stores each ZIP entry as bytes and save emits all parts. | Reconstructing only known document parts loses extensions, media, and vendor data. | Treat package parts as opaque bytes; replacement is opt-in. | Exact DOCX unknown-part sentinel save round-trip is verified; XLSX and PPTX per-format save sentinels remain pending. | ZIP metadata/order/compression may change; part payload preservation, not byte-identical archive preservation, is the guarantee. |
| Resource bounds and integrity | Malicious compressed packages can cause excessive memory use or carry corrupt payloads. | `ArchivePolicy` bounds metadata before allocation, extraction enables CRC checks, and post-extraction output must match metadata. | Dependency defaults alone did not express the product's trust boundary and CRC was opt-in. | Route all public opens through conservative defaults and expose explicit stricter policy variants. | Hostile and exact-boundary policy fixtures plus existing save/reopen coverage. | The whole archive remains in memory; dependency hard ceilings also apply. |

## Compatibility matrix

| Capability | DOCX | XLSX | PPTX | Status |
|---|---:|---:|---:|---|
| Prefix-tolerant lexical local-name lookup | Yes | Yes | Yes | Implemented; broader fixtures pending |
| Root and part relationships | Yes | Yes | Yes | Implemented; nested/URI edge tests pending |
| Relative internal targets | Yes | Yes | Yes | Implemented for path segments |
| External relationship marking | Yes | Yes | Yes | Parsed, caller policy remains format-specific |
| Unknown binary/XML part preservation | Yes | Yes | Yes | Payload-preserving package model; exact DOCX unknown-part sentinel save round-trip verified; XLSX/PPTX per-format save sentinels pending |
| Duplicate/traversal ZIP rejection | Yes | Yes | Yes | Implemented; black-box fixture coverage pending |
| Lexically identical XML round-trip | No | No | No | Out of scope for current semantic XML model |
| Bounded pre-allocation ZIP extraction | Yes | Yes | Yes | MoonLeaf policy preflight plus dependency hard ceilings |
| Mandatory ZIP CRC verification | Yes | Yes | Yes | Enabled on every public open |

## Remaining production gaps

1. Expand the current synthetic fixtures—which already have content types, root and nested relationships, media/custom XML, and unknown vendor parts—with comments, CDATA, entities, broader producer variations, and more per-format save sentinels.
2. Add black-box malformed/truncated XML matrices and broaden corrupt
   central-directory cases beyond the implemented hostile ZIP policy suite.
3. Follow up on the implemented XML limits: explicitly qualify `max_input_utf16` as UTF-16 code units, and add stress and boundary tests for all configured limits.
4. Add host/process isolation for external resources and active content; the
   implemented archive policy is not a semantic sandbox.
5. Validate content types, relationship ID uniqueness, relationship root namespace, and internal target existence where format policy requires it.
6. Define URI handling for fragments, queries, percent encoding, and any other unimplemented URI semantics.
7. Run and record `moon fmt`, `moon info`, `moon check --target all --warn-list +73`, separate full tests with `moon test --target wasm`, `moon test --target wasm-gc`, `moon test --target js`, and `moon test --target native`, the focused native PPTX regression, and `git diff --check`; aggregate `all` must not be the sole test evidence.

## Current checkpoint corrections

The `8276895` paragraph above records a prior checkpoint and is not a statement
about current HEAD. Source fixtures and editor-session coverage are present.
The 93/93-per-target result is the prior broad baseline; the current focused
archive-policy result is recorded at the top of this file. The earlier focused
native PPTX regression proves that identical replacement of entity-coded
`A&#66;` with rendered `AB` preserves exact slide XML bytes.

The audited hidden-edit regression proves that a DOCX `w:t` edit inside a viewer-ignored top-level `w:sdt` is committed and survives save even when the scene is unchanged. `commit_candidate` now uses candidate `Package` difference; XLSX retains semantic no-ops through its operation-specific exact existing Text-cell precheck.

Evidence boundaries: nested-mutation isolation covers representative XLSX cells, diagnostics, and `VerifiedDocumentCopy::bytes()`, not every nested shape. Failed-edit byte equality is proved for the tested formula-cell prevalidation failure. Exact unknown-part save preservation is currently evidenced for DOCX; shared verification runs for all formats, and per-format sentinel saves remain follow-up work.
