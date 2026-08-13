# MoonLeaf responsibility and testability

MoonLeaf is conservative OOXML functionality consumed by a host. It owns file
interpretation, neutral scenes, bounded edits, and verified save-as-copy. It
does not own a standalone Office clone, file picker, desktop permissions, or
rendering application. It does own the evidence contract for any print-ready
render represented as a MoonLeaf result. Host applications must not substitute
LibreOffice, Word, or another office engine and label the result MoonLeaf.

## Package ownership

| Package | Responsibility | Deliberate boundary |
| --- | --- | --- |
| root package | public document/session facade and save/reopen verification | coordinates formats without absorbing their parsing rules |
| `xml` | XML tokenization, typed nodes, and serialization | no OPC path or archive policy |
| `opc` | ZIP/OPC policy, path containment, relationships, CRC and package access | no document-format semantics |
| `scene` | host-neutral document, sheet, and slide projection types | no Rabbita widgets or desktop drawing |
| `docx` | WordprocessingML read, ordered rich preview metadata, inspect, and bounded text edit | unsupported layout remains explicit |
| `xlsx` | SpreadsheetML read, inspect, and bounded cell edit | no formula recalculation engine |
| `pptx` | PresentationML read, inspect, and exact text replacement | no animation or full layout engine |

Public format and scene types stay in their public packages. A convenience
facade may re-export them, but private archive helpers must not become public
type owners.

## Test seams

| Responsibility | Focused evidence |
| --- | --- |
| archive safety | traversal, alias, size, count, compression, CRC, and relationship denial fixtures |
| format interpretation | per-format black-box fixtures from known producers and malformed inputs |
| conservative edit | edit only the declared target and retain unsupported package parts |
| save recovery | save as a new copy, reopen with the same policy, and compare the neutral scene |
| host integration | MoonDesk opens, previews, edits, chooses a destination, and displays diagnostics |

Fixture success establishes parser and preservation behavior only. Malicious
document isolation, macros, signatures, external resources, and real-producer
coverage remain separate host and qualification obligations; they must not be
inferred from a successful in-memory parse.
