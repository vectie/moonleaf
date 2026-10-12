# MoonLeaf documentation

- [Product contract](PRODUCT_CONTRACT.md) — format matrix, security boundary and
  MoonDesk host boundary.
- [Responsibility and testability](RESPONSIBILITY_AND_TESTABILITY.md) — package
  ownership, parser/save seams, and the deliberate non-application boundary.
- [Archive security](ARCHIVE_SECURITY.md) — exact per-open policy, integrity
  sequence, defaults and non-claims.
- [Preservation matrix](PRESERVATION_MATRIX.md) — what survives save/reopen and
  what MoonLeaf does not promise.
- [Production progress](PRODUCTION_PROGRESS.md) — current work-package status.
- [Session problem/fix ledger](SESSION_PROBLEM_FIX_LEDGER.md) — verified session
  behavior and known failures.
- [`engineering/problem-fix-ledger/`](engineering/problem-fix-ledger/) — XML,
  OPC, DOCX, XLSX, PPTX and integration evidence.
- [JSON tables](JSON_TABLES.md) — typed JSON/JSONL projection and CSV/XLSX export.
- [Lookup tables](LOOKUP_TABLES.md) — exact-key cross-file enrichment.
- [Summary tables](SUMMARY_TABLES.md) — reusable grouped counts, sums and means,
  JSON interchange, and a Node CLI for imported CSV/TSV/JSON/JSONL.
- [XML records](XML_RECORDS.md) — bounded, mapped supplier/order XML intake into
  reusable tables, CSV, JSON and XLSX, with a Node CLI.
- [Unpivot tables](UNPIVOT_TABLES.md) — turn wide month/question columns into
  reusable name/value rows, with a JSON-spec CLI and native library example.
- [Pivot tables](PIVOT_TABLES.md) — widen long entity/key/value observations into
  an ordered comparison with explicit duplicate policy and CSV/JSON/XLSX output.

- [Stack tables](STACK_TABLES.md) — append real file inputs by strict or union headers,
  preserving source-row provenance and scalar types.
- [Reconcile tables](RECONCILE_TABLES.md) — compare two snapshots by exact composite
  keys, reviewing added/removed/changed/unchanged records with before/after values.

- [Reusable filter, sort and projection recipes](QUERY_TABLES.md)
- [Consolidate overlapping exports](CONSOLIDATE_TABLES.md) — explicit composite
  keys, keep-first/keep-last complete rows and a source-linked disposition report.

- [Nested JSON record intake](JSON_RECORDS.md): select an offline envelope array and explicit nested scalar fields; export CSV, JSON or typed XLSX.

- [Typed table corrections](CORRECT_TABLES.md): correct selected cells by exact keys and expected old values, with a before/after report and copy exports.

- [Explicit typed CSV/TSV import](TYPED_DELIMITED.md): reusable column selection,
  renaming, numeric and Boolean conversion, null markers and fresh table exports.

- [Presentation review outlines](PRESENTATION_OUTLINE.md): export ordered PPTX
  text, tables and speaker notes to source-linked JSON or Markdown.

- [Compare original and client-copy workbooks](COMPARE_WORKBOOKS.md): source-hashed
  before/after cell content, formula versus cache changes, sheet changes and merges,
  with readable or JSON output and explicit comparison limits.

- [PowerPoint table intake](PPTX_TABLES.md): discover and select a slide table,
  query its literal text, and export CSV/JSON/XLSX with slide and row references.

- [Import JSON line items with parent context](JSON_LINES.md)

- [Pseudonymized client copies](PSEUDONYMIZED_CLIENT_COPY.md): consistent per-file
  identity tokens and column masks, producing existing typed correction recipes
  and source-bound fresh CSV/TSV copies with text-value reopen evidence.

- [Editable CSV/TSV review sheets](REVIEW_SHEETS.md): export a scoped sheet,
  import exact keyed edits into typed corrections, and reopen a fresh full copy.

- [Choose reviewed cell edits](SELECT_REVIEW_EDITS.md): accept/reject individual
  proposals and apply the accepted subset through the existing verified-copy lane.

- [Carry reviewed edits onto a newer source](REBASE_REVIEW_EDITS.md): three-way
  cell review, explicit conflict choices and an existing current-bound proposal.

- [Combine independent reviewed corrections](MERGE_REVIEW_EDITS.md): merge
  exact proposed cells with explicit conflict choices into the existing copy lane.

- [Review assigned record batches](REVIEW_BATCHES.md): expose only explicit keys,
  context and editable values, then prepare ordinary full-source proposals.
