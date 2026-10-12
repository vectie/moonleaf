# MoonLeaf product contract

Class: library/functionality
Maturity: conservative OOXML alpha
Last reviewed: 2026-07-31

## Outcome

MoonLeaf lets MoonDesk preview DOCX, XLSX and PPTX files and make deliberately
small, verified edits while preserving unrecognized package parts where
possible.

## Ownership

MoonLeaf owns ZIP/OPC parsing, path safety, neutral scenes, conservative format
readers/editors and save-as-copy verification. It does not own an Office-like
UI, host file permissions, advanced layout engines, formula recalculation,
macros, signatures or document collaboration.

## Capability status

| Capability | Status |
| --- | --- |
| DOCX paragraph/table preview and bounded text replacement | available |
| Source-bound single DOCX text-element correction and copy CLI | available subset; see [targeted DOCX](TARGETED_DOCX.md) |
| Ordered rich DOCX preview metadata for host renderers | available |
| Selected DOCX body-table import, query and CSV/JSON/XLSX export | available text subset; see [DOCX tables](DOCX_TABLES.md) |
| XLSX common cell/formula/style preview, inline-text cell edit, verified batch replacement of existing text cells, and bounded whole-column insert/delete copies | available; batch replacement preserves formula cells; column shifts reject formulas and anchored references |
| Named Excel Table discovery, query and CSV/JSON/XLSX dataset export | available value subset; see [named Excel Tables](NAMED_XLSX_TABLES.md) |
| Source-bound atomic XLSX text-correction recipe and verified-copy CLI | available ordinary-text subset; see [workbook text correction](CORRECT_WORKBOOK_TEXT.md) |
| Read-only original/client-copy XLSX content comparison | available subset; see [workbook comparison](COMPARE_WORKBOOKS.md) |
| CSV/TSV UTF-8 table preview, bounded parser, serialization, whole-table text replacement, and verified whole-column insert/delete copies | available |
| PDF text extraction to page-oriented Markdown (native, JS, Wasm-GC) | available; no OCR or layout fidelity |
| Editable CSV/TSV review-sheet round trip into exact typed corrections and fresh full copies | bounded Python host adapter; text-value readback, no reviewer authentication or render qualification; see [review sheets](REVIEW_SHEETS.md) |
| Explicit CSV/TSV record-batch review with immutable context and ordinary full-source proposals | bounded Python host adapter; selected reviewer export, no authenticated approval or sharing authority; see [review batches](REVIEW_BATCHES.md) |
| Carry a frozen CSV/TSV review proposal onto a newer source with explicit cell conflict choices | bounded Python host adapter; current-bound existing apply, no automatic row resurrection or authenticated approval; see [review rebase](REBASE_REVIEW_EDITS.md) |
| Selective accept/reject review of proposed CSV/TSV cell changes | bounded Python host adapter feeding existing proposal/apply; no authenticated approval; see [choose reviewed edits](SELECT_REVIEW_EDITS.md) |
| Consistent pseudonym/mask policies to existing cell-correction recipes and fresh CSV/TSV client copies | bounded Python host adapter; exact core recipe compatibility tested, not document-session or anonymity qualification; see [client copies](PSEUDONYMIZED_CLIENT_COPY.md) |
| Fixed-width ASCII report import, query and CSV/JSON/XLSX dataset export | available explicit-width text subset; see [fixed-width records](FIXED_WIDTH.md) |
| Markdown pipe-table discovery, query and CSV/JSON/XLSX dataset export | available literal-text subset; see [Markdown tables](MARKDOWN_TABLES.md) |
| Nested JSON line-item import with parent context, query and dataset export | available explicit-mapping subset; see [JSON line items](JSON_LINES.md) |
| PPTX slide/text/shape/picture preview and exact text replacement | available |
| Selected PowerPoint table import, query and CSV/JSON/XLSX export | available literal-text subset; see [PowerPoint tables](PPTX_TABLES.md) |
| Save-as-copy, reopen and re-render verification | available |
| Typed MoonLeaf PDF/page render evidence contract | available |
| Native DOCX PDF bytes with embedded static TrueType and bounded legal layout | implemented subset; see render/README.mbt.md; exact-template production visual acceptance still required |
| Full Office typography, shaping and print fidelity | not claimed; unsupported features fail closed |
| Strict per-open ZIP/OPC policy and mandatory CRC verification | available |
| Advanced charts, layout, animations and recalculation | excluded/planned |

## Security and fidelity

Unknown OPC part payloads are intended to survive save-as-copy, but
byte-identical ZIP layout, macros, encryption, signatures and
application-specific metadata are not guaranteed.

All public opens use conservative `ArchivePolicy` defaults. MoonLeaf preflights
central-directory metadata, rejects policy/path/alias violations, enables
per-entry CRC verification during extraction, and checks extracted names and
sizes against the preflight view. Hosts can pass stricter policies through
`open_with_policy` and `open_session_with_policy`; a session retains that policy
for its verified save/reopen step.

This is an in-memory ZIP/OPC resource and integrity boundary, not a general
malicious-document sandbox. MoonLeaf does not claim macro analysis, signature
validation, encryption support, external-resource isolation, or semantic safety
for unsupported OOXML features.

Format-specific worktrees are development branches of MoonLeaf, not separate
products.

## Host contract

MoonDesk owns file access, user confirmation, conflict handling and save
destination. MoonLeaf returns neutral scenes, diagnostics, capabilities and
verified copies. A host that requires print-ready DOCX pagination must accept
only a typed `moonleaf.render-evidence.v1` receipt from the MoonLeaf renderer;
another office engine is not an interchangeable implementation. Until
MoonLeaf's supported layout/font/PDF profile covers a document, this capability
is fail-closed rather than delegated. Its native PDF implementation now exists;
production qualification still requires genuine fonts and real visual acceptance.

## Verification

```sh
moon check --target all
moon test --target all
moon info
moon fmt
```

## Release gates and next milestones

- Integrate policy diagnostics and open-edit-save-reopen into MoonDesk.
- Add host-level isolation for external relationships and active content.
- Expand real-producer and malformed OOXML fixtures beyond the ZIP/OPC boundary.
- Extend the preservation matrix only when format-specific evidence exists.
