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
| XLSX common cell/formula/style preview and inline-text cell edit | available |
| PPTX slide/text/shape/picture preview and exact text replacement | available |
| Save-as-copy, reopen and re-render verification | available |
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

MoonDesk owns file access, user confirmation, rendering, conflict handling and
save destination. MoonLeaf returns neutral scenes, diagnostics, capabilities
and verified copies.

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
