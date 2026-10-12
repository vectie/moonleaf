# Fixed-width business export intake

`jsontable.parse_fixed_width_schema` and `parse_fixed_width` import a bounded
ASCII fixed-width report into the existing query and CSV/JSON/XLSX pipeline.
No existing importer accepts adjacent column widths. This is useful for legacy
supplier, inventory and billing exports that have padding instead of delimiters.

Schema v1 has exactly `version`, `skip_lines`, `blank_lines`, and `columns`.
Each ordered column has exactly a unique nonempty `name`, a positive integer
`width`, and Boolean `trim`. Widths are adjacent, starting at position 1; the sum
must equal every retained record's width. There is no implicit dropped suffix,
padding, guessed delimiter, number conversion or formula evaluation. `trim`
removes edge ASCII spaces only. Values remain text, including `001` and `=1+1`.

`skip_lines` explicitly skips 0–100 physical leading lines. `blank_lines` is
`skip` (empty or all-space lines) or `reject` (no special skipping; every line
must meet the exact width, so a full-width all-space record is valid). Both
leading and blank skipped physical line numbers are returned. A terminal LF is
not an extra blank record. LF/CRLF are accepted; bare CR, tabs, controls, BOM and
non-ASCII are refused even in skipped headers. Thus widths are unambiguous ASCII
positions, not Unicode display widths. No EBCDIC conversion or continuation,
footer detection, variable record type, or fixed-width writeback is included.

Limits: input 4,000,000 UTF-16 units (CLI 4,000,000 bytes), schema 65,536 units
(CLI bytes), 1–128 columns, name up to 256 units, total width 1–4096,
100,000 output cells including headers. All records are validated before query
or output, even those subsequently filtered out. Empty data after skipped
headers is valid. Fewer lines than `skip_lines` is an error.

Node CLI:

```
node fixed-width.js inspect INPUT SCHEMA.json
node fixed-width.js export INPUT SCHEMA.json SOURCE_SHA256 QUERY.json|- csv|json|xlsx FRESH_OUTPUT
```

Inspect shows source/schema digests, columns, all parsed data (bounded by the
above limits), source and skipped physical lines, and warnings. Export requires
the exact source SHA-256 from inspection, takes the explicitly supplied schema,
and records that schema and digest plus query/digest, output digest, counts and
selected physical lines. Inspect again if source or schema changes. This does
not enforce prior schema-review identity: the export's explicit schema is the
one used, and the receipt records it. Query sorting/filtering maps output back
to original physical lines. `-` selects all records.

Existing destinations, including source/schema, are refused by exclusive
creation. Byte readback follows writing; keep any failed-write file and retry
a fresh destination. Original input is never rewritten. Prefer XLSX for literal
strings; CSV applications can reinterpret formula-looking text. Empty JSON is
`[]`; use receipt columns to retain its schema.

This adds bounded W05 intake, not MoonDesk integration, real-producer acceptance,
source completeness, original-format fidelity, document-session render
verification, print readiness or customer acceptance.
