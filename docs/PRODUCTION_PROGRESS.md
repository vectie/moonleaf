# Production hardening progress

This ledger records reproduced XML/OPC defects, fixes, verification, and remaining risks. It is intentionally evidence-based and should be updated with every hardening slice.

Current verification: 37/37 tests pass on each of wasm, wasm-gc, JavaScript, and native (148 target-test executions). DOCX inspection coverage now includes style cascade/default paragraph styles, structure and numeric fallback, table spans, relationship parse failures, and image-target diagnostics. Detailed DOCX evidence and residual limits are recorded in `docs/engineering/problem-fix-ledger/WP04-docx-viewer.md`.

## Problem/fix ledger

| Area | Symptom | Reproduction / evidence | Root cause | Fix | Verification | Residual risk |
|---|---|---|---|---|---|---|
| XML truncation | Truncated declarations, comments, CDATA, attributes, and elements must fail rather than return a partial tree. | Parser audit: all terminator scans and closing-tag checks are raising paths. Regression tests are required for every construct. | Streaming-by-offset parser needs every delimiter path to be explicit. | Existing strict delimiter checks retained; black-box truncation corpus remains the next test addition. | Pending target-wide regression run. | Configurable limits now exist; recursive parsing still relies on the configured depth ceiling. |
| WP01 XML record compatibility | Native compilation failed when namespace expansion fields were added to legacy `Element`/`Attribute` construction and duplicate detection referenced unbound `aname`. | Native compiler reported incompatible-record, missing-field, and unbound-name errors. | Prefix-tolerant lexical QName work crossed the public legacy record boundary. | In `Parser::parse_element`, keep `Array[Attribute]`, compare `a.name == n`, push only `{ name: n, value: v }`, and return inferred legacy `{ name: qname, attributes: attrs, children }` records; rename the unused scope parameter to `_parent_scope`. No namespace fields are added and `parse_namespaced` remains unimplemented. | `moon fmt`; `moon check --target all`; `moon test --target all`: wasm 28/28, wasm-gc 28/28, js 28/28, native 28/28; `git diff --check`. | URI-aware parsing remains deferred to a separate `parse_namespaced` API; lexical namespace declarations are retained for round trips. |
| Prefix-tolerant lexical local-name lookup | OOXML callers commonly bind arbitrary prefixes and must match schema local names. | `Element::local_name`, `attribute`, and child lookup are local-name tolerant. | OOXML producers freely vary namespace prefixes. | Existing local-name lookup behavior retained as compatibility boundary. | Prefixed parse/serialize namespace-retention regression test added. | Namespace URI identity is not represented, so two same-local-name attributes from different namespaces can be ambiguous. |
| XML lexical content | Declarations/comments are discarded and CDATA is represented as text during parse/save. | Parser/serializer audit. | The current XML model stores elements, attributes, and text, not lexical trivia. | Preserve semantic text and safely escape it on serialization. | Pending entity/CDATA round-trip tests. | Exact lexical round-trip is unsupported and documented rather than falsely promised. DTD/entity declarations must remain unsupported for safety. |
| OPC ZIP paths | Absolute and parent-traversal ZIP entry names can escape a logical package namespace. | `open_package` and `save_package` reject leading separators and `..` segments. | ZIP names are untrusted and normalization alone can hide traversal. | Reject unsafe names before normalization on read and write. | Pending generated malicious-ZIP tests. | Unicode/case aliases are platform-sensitive; package lookup remains exact and case-sensitive per OPC conventions. |
| OPC duplicates | Two ZIP entries can normalize to the same part and create parser ambiguity. | Package open checks every normalized part name for duplication. | ZIP permits duplicate names and slash variants. | Reject normalized duplicate parts. | Pending duplicate and backslash-alias fixtures. | Check is currently quadratic in part count; large-package indexing is a future optimization. |
| OPC required metadata | A ZIP without `[Content_Types].xml` is not a valid OPC package. | Open/save explicitly reject its absence. | ZIP validity alone is insufficient for OPC validity. | Enforce the required content-types part at both boundaries. | Pending malformed-package fixture. | Content-type declarations themselves are not yet semantically validated. |
| OPC relationships | Internal relative targets must resolve against the source part; external targets must not be treated as package parts. | Relationship parser records `TargetMode`; `resolve_target` joins against the source directory. | Relationship targets are URI references, not ZIP-root paths by default. | Existing relative resolution retained; URI-fragment/query and percent-encoding tests remain required. | Pending nested DOCX/XLSX/PPTX fixtures. | Full RFC 3986 canonicalization and rejection of traversal above package root are not yet exposed as a raising API. |
| Save preservation | Unknown OOXML parts must survive load/edit/save byte-for-byte unless explicitly replaced. | `Package` stores each ZIP entry as bytes and save emits all parts. | Reconstructing only known document parts loses extensions, media, and vendor data. | Treat package parts as opaque bytes; replacement is opt-in. | Pending unknown-part sentinel round-trip test. | ZIP metadata/order/compression may change; part payload preservation, not byte-identical archive preservation, is the guarantee. |
| Resource bounds | Malicious compressed packages can cause excessive memory use. | Current `fzip.unzip_sync` materializes entries; no verified streaming/limit API has been established. | Dependency surface currently used by the package is whole-archive decompression. | Strongest verified boundary today is path/duplicate/required-part validation immediately after decompression. | Pending dependency capability investigation and stress tests. | Compressed/uncompressed byte, entry-count, and ratio limits are not enforceable before allocation with the currently verified API. This is a release blocker for hostile-input service use. |

## Compatibility matrix

| Capability | DOCX | XLSX | PPTX | Status |
|---|---:|---:|---:|---|
| Prefix-tolerant lexical local-name lookup | Yes | Yes | Yes | Implemented; broader fixtures pending |
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
3. Follow up on the implemented XML limits: explicitly qualify `max_input_utf16` as UTF-16 code units, and add stress and boundary tests for all configured limits.
4. Investigate fzip-supported extraction metadata/limits; if unavailable, isolate decompression behind a size-limited API or replace the dependency.
5. Validate content types, relationship ID uniqueness, relationship root namespace, and internal target existence where format policy requires it.
6. Define URI handling for fragments, queries, percent encoding, and traversal above package root with a coherent raising API.
7. Run and record `moon fmt`, `moon info`, `moon check --target all --warn-list +73`, `moon test --target all`, and `git diff --check` after the test/fixture slice lands.
