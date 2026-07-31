# Preservation truth

MoonLeaf preserves package-part payloads, not the original ZIP byte stream.
`DocumentSession::save_as_copy` serializes, opens again under the session's
archive policy, rerenders, and verifies exact part-name/payload equality before
returning a clean session.

| Item | Current guarantee | Evidence boundary |
| --- | --- | --- |
| Known unedited OPC part payload | Preserved byte-for-byte | Shared package save/reopen |
| Unknown OPC part payload | Preserved byte-for-byte unless explicitly replaced | Generic OPC fixture and DOCX custom/binary sentinels |
| Edited part payload | Semantically validated for the supported edit | DOCX/PPTX text and XLSX inline-text tests |
| Part name set | Equal after verified session save/reopen | `same_parts` verification |
| Rendered neutral scene | Equal after verified session save/reopen | Session verification |
| ZIP order, compression, timestamps, comments and extra fields | Not guaranteed | Archive is rebuilt |
| XML lexical form of an edited part | Not generally guaranteed | XML may be serialized |
| Macros/VBA behavior | Not supported or guaranteed | No macro analysis |
| Digital-signature validity | Not preserved or validated | Repacking/editing can invalidate signatures |
| Encryption | Unsupported | No encrypted-package contract |
| External relationships or fetched resources | Not followed or safety-qualified by this guarantee | Host policy required |
| Application-specific metadata semantics | Not guaranteed | Unknown bytes may survive without semantic interpretation |

The current exact unknown-part sentinel is strongest for DOCX plus the
format-neutral OPC layer. XLSX and PPTX use the same package mechanism, but
format-specific unknown-part sentinel breadth should only be claimed after
dedicated fixtures are added.
