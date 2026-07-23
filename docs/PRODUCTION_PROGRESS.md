# Production hardening progress

This ledger records reproduced XML/OPC defects, fixes, verification, and remaining risks. It is intentionally evidence-based and should be updated with every hardening slice.

WP06 XLSX relationship/type/OPC hardening is complete. Public `xlsx.read` now shares inspect's exact official transitional+purl relationship policy (external exclusion, relocation, duplicate-authority rejection, and declared-target failure), and OPC rejects both relative and leading-slash above-root traversal. Final matrix evidence is green: every native/wasm/wasm-gc/js check exits 0 with exactly 73 warning diagnostics; XLSX passes 32/32 per target (128 focused target-test executions); and the full repository passes 51/51 per target (204 full target-test executions). `moon info` recreated EOF-only blank lines in generated interfaces; after reviewing its semantic output, the six unrelated generated interfaces were restored to branch baseline and only the XLSX interface EOF blank line was removed. It was intentionally not rerun after that cleanup because it would recreate the known whitespace defect.

## Problem/fix ledger

| Area | Symptom | Reproduction / evidence | Root cause | Fix | Verification | Residual risk |
|---|---|---|---|---|---|---|
| XML truncation | Truncated declarations, comments, CDATA, attributes, and elements must fail rather than return a partial tree. | Parser audit: all terminator scans and closing-tag checks are raising paths. Regression tests are required for every construct. | Streaming-by-offset parser needs every delimiter path to be explicit. | Existing strict delimiter checks retained; black-box truncation corpus remains the next test addition. | Full repository validation passes 51/51 on native, wasm, wasm-gc, and js. | No configurable input/depth/node limits yet; deeply nested hostile XML may exhaust stack/resources. |
| XML namespaces | OOXML callers commonly bind arbitrary prefixes and must match schema local names. | `Element::local_name`, `attribute`, and child lookup are local-name tolerant. | OOXML producers freely vary namespace prefixes. | Existing local-name lookup behavior retained as compatibility boundary. | Pending prefixed/default namespace fixture tests. | Namespace URI identity is not represented, so two same-local-name attributes from different namespaces can be ambiguous. |
| XML lexical content | Declarations/comments are discarded and CDATA is represented as text during parse/save. | Parser/serializer audit. | The current XML model stores elements, attributes, and text, not lexical trivia. | Preserve semantic text and safely escape it on serialization. | Pending entity/CDATA round-trip tests. | Exact lexical round-trip is unsupported and documented rather than falsely promised. DTD/entity declarations must remain unsupported for safety. |
| OPC ZIP paths | Absolute and parent-traversal ZIP entry names can escape a logical package namespace. | `open_package` and `save_package` reject leading separators and `..` segments. | ZIP names are untrusted and normalization alone can hide traversal. | Reject unsafe names before normalization on read and write. | Pending generated malicious-ZIP tests. | Unicode/case aliases are platform-sensitive; package lookup remains exact and case-sensitive per OPC conventions. |
| OPC duplicates | Two ZIP entries can normalize to the same part and create parser ambiguity. | Package open checks every normalized part name for duplication. | ZIP permits duplicate names and slash variants. | Reject normalized duplicate parts. | Pending duplicate and backslash-alias fixtures. | Check is currently quadratic in part count; large-package indexing is a future optimization. |
| OPC required metadata | A ZIP without `[Content_Types].xml` is not a valid OPC package. | Open/save explicitly reject its absence. | ZIP validity alone is insufficient for OPC validity. | Enforce the required content-types part at both boundaries. | Pending malformed-package fixture. | Content-type declarations themselves are not yet semantically validated. |
| OPC relationships | Internal relative targets must resolve against the source part; external targets must not be treated as package parts. | Relationship parser records `TargetMode`; the raising `resolve_target` API joins against the source directory and rejects above-package-root traversal for both relative and leading-slash targets. | Relationship targets are URI references, not ZIP-root paths by default. | Existing relative resolution and traversal rejection retained; URI fragment/query/percent-encoding canonicalization remains pending. | Pending nested DOCX/XLSX/PPTX fixtures. | Full RFC 3986 canonicalization for fragments, queries, percent encoding, and other unimplemented URI semantics is not yet provided. |
| Save preservation | Unknown OOXML parts must survive load/edit/save byte-for-byte unless explicitly replaced. | `Package` stores each ZIP entry as bytes and save emits all parts. | Reconstructing only known document parts loses extensions, media, and vendor data. | Treat package parts as opaque bytes; replacement is opt-in. | Pending unknown-part sentinel round-trip test. | ZIP metadata/order/compression may change; part payload preservation, not byte-identical archive preservation, is the guarantee. |
| Resource bounds | Malicious compressed packages can cause excessive memory use. | Current `fzip.unzip_sync` materializes entries; no verified streaming/limit API has been established. | Dependency surface currently used by the package is whole-archive decompression. | Strongest verified boundary today is path/duplicate/required-part validation immediately after decompression. | Pending dependency capability investigation and stress tests. | Compressed/uncompressed byte, entry-count, and ratio limits are not enforceable before allocation with the currently verified API. This is a release blocker for hostile-input service use. |

## Compatibility matrix

| Capability | DOCX | XLSX | PPTX | Status |
|---|---:|---:|---:|---|
| Namespaced XML local-name lookup | Yes | Yes | Yes | Implemented; broader fixtures pending |
| Root and part relationships | Yes | Yes | Yes | Implemented; nested/URI edge tests pending |
| Relative internal targets | Yes | Yes | Yes | Implemented for path segments |
| External relationship marking | Yes | Yes | Yes | Parsed, caller policy remains format-specific |
| Unknown binary/XML part preservation | Yes | Yes | Yes | Payload-preserving package model; round-trip fixture pending |
| Duplicate/traversal ZIP rejection | Yes | Yes | Yes | Implemented; black-box fixture coverage pending |
| Lexically identical XML round-trip | No | No | No | Out of scope for current semantic XML model |
| Bounded pre-allocation ZIP extraction | No | No | No | Unsupported by verified fzip usage; documented limitation |

## Remaining production gaps

1. Add generated, real-world-shaped DOCX/XLSX/PPTX fixtures containing content types, root relationships, nested part relationships, media/custom XML, comments, CDATA, entities, and unknown vendor parts.
2. Add black-box malformed/truncated XML matrices and malicious ZIP tests (duplicates, aliases, traversal, missing parts, corrupt central directory, and decompression stress).
3. Introduce explicit XML limits (input bytes, nesting depth, attributes, nodes, and expanded text) without breaking existing callers.
4. Investigate fzip-supported extraction metadata/limits; if unavailable, isolate decompression behind a size-limited API or replace the dependency.
5. Validate content types, relationship ID uniqueness, relationship root namespace, and internal target existence where format policy requires it.
6. Define URI handling for fragments, queries, percent encoding, and any other unimplemented URI semantics.
7. Run and record `moon fmt`, `moon info`, `moon check --target all --warn-list +73`, `moon test --target all`, and `git diff --check` after the test/fixture slice lands.
