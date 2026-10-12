# Review an original workbook against a client copy

Use MoonLeaf's read-only comparison to find changed spreadsheet content before
reviewing a client copy: which cell changed, its original and copied value, and
whether a formula expression changed or only its stored cached result did.
The report retains exact source hashes. Neither input is rewritten or calculated.

This extends the PRD W06/R02 original/client-copy inspection workflow and B05's
separation of values, formulas and unknown calculation freshness. It is a library
and local Node adapter, not a new MoonDesk UI or a copy-verification approval.

## Run

Build only the adapter, with a correctly pinned graph and external build target:

```sh
moon -C /absolute/moonleaf --target-dir /absolute/build build cmd/xlsx-compare --target js --frozen --strip -j 1
node /absolute/build/js/debug/build/cmd/xlsx-compare/xlsx-compare.js original.xlsx client-copy.xlsx text
node /absolute/build/js/debug/build/cmd/xlsx-compare/xlsx-compare.js original.xlsx client-copy.xlsx json > /fresh/comparison.json
```

Arguments are `ORIGINAL.xlsx CLIENT_COPY.xlsx [json|text]`; JSON is the default.
Both are explicit regular-file paths; stdin and URL input are not supported.
The CLI reads each file once, compares the same in-memory bytes it hashes, and
writes only a completed report to stdout. Invalid or unsupported input exits
nonzero with stderr diagnostics and no partial stdout report. It does not write
workbooks, reports to a selected path, or any external service.

Choose a fresh report destination. Shell redirection happens before the CLI runs
and can truncate an input if pointed at it. File permissions, confirmation,
conflict handling, destinations, source retention and delivery remain the host's
responsibility. Separate invocations reread their inputs; compare their hashes.

## Read the result

The retained example under `kit/workbook-compare/` has six cell changes and
sheet/merge changes. In the readable report:

```text
D2 [formula]
  before: formula "C2*2" attributes={}; stored number cache="25"
  after:  formula "C2*3" attributes={}; stored number cache="25"
E2 [cached_value]
  before: formula "SUM(C2:C3)" attributes={}; stored number cache="20"
  after:  formula "SUM(C2:C3)" attributes={}; stored number cache="21"
```

D2's unchanged cache is not evidence that the new expression evaluates to 25.
E2's changed cache is not evidence of recalculation. Both remain stored tokens
whose freshness is unknown. Quoted text uses JSON escaping so embedded newlines,
quotes and control characters cannot masquerade as additional report lines.

The JSON envelope is `moonleaf.workbook-comparison.v1`:

- `original_sha256` and `copy_sha256` identify the exact compared byte buffers.
- `identical_bytes` compares the complete bytes. This is independent of content.
- `supported_content_changed` is true for a reported sheet/cell change or a
  workbook date-system change. False does not mean equivalent workbooks.
- `comparison.before_sheets` and `after_sheets` retain ordered exact sheet names.
- `comparison.sheets` contains changed sheets in original order, then new sheets
  in copy order. Each records before/after one-based position, visibility, merged
  ranges, change categories and changed cells. Added/removed empty sheets remain
  visible even with no cell differences.
- Cells are sorted by numeric row then column, regardless of XML element order.
  Each has `address`, `before`, `after` and `changes`. Absent cell snapshots and
  missing optional payloads are JSON null, not strings or one-element arrays.
- `value_type` is `text`, `number`, `boolean`, `error`, `date` or `empty`.
  `value` is a string token or null. `formula` is the exact formula text or null;
  an empty shared-formula follower has `formula: ""` and is still a formula.
  `formula_attributes` includes the declared formula attributes such as shared
  index, type and range; these are compared separately from the expression.
- Cell categories are `added`, `removed`, `value`, `formula`,
  `formula_metadata` and `cached_value`. Cache changes are labeled
  `cached_value` when both sides are formulas. Formula-to-value or value-to-formula
  transitions use `formula` plus `value` if the payload or its type changed.
  Several categories can apply to one cell; `changed_cells` counts cells once.
- `before_date1904`, `after_date1904` and `date_system_changed` expose the workbook
  date-epoch setting. Dates are not converted or formatted.
- `warnings` always travels with the report, including an unchanged result.

## Matching and scope

Names are exact and case-sensitive. A rename appears as removed and added sheets;
inserted/deleted rows are not semantically aligned. Cells are compared by canonical
A1 coordinates, including the full sparse A1:XFD1048576 grid. No dense million-row
array is allocated. Ordinary implicit row/cell coordinates are resolved according
to their order. Logical coordinate aliases cannot pick a winning duplicate.
Hidden and very-hidden worksheets and hidden rows/columns are included.

Only direct `sheetData/row/c` content is compared. Shared strings are resolved,
so reindexing the same text does not create a change. Inline/shared rich text is
flattened; formatting changes do not count as text edits. Nonformula booleans
normalize valid lexical spellings; numbers and ISO date cells retain exact raw
strings, so `1.0` and `1` differ. Formula caches retain their original type/token,
without numeric or Boolean normalization. Error values remain distinguishable
from text. This reports payloads, not full validity of every Office value token.

Explicit empty cells differ from absent cells. An empty text string differs
from an empty cell or missing formula cache. Consequently adding a styled blank
cell can report a cell addition even though styles themselves are excluded.
Merge references are canonicalized and sorted; their XML order is insignificant.
The default workbook date system is equivalent to an explicit false setting.

Styles, number-format definitions, rich text formatting, comments, charts,
hyperlinks, named ranges, filters, drawings, wrapped/extension content and other
package parts are not compared. A style-only workbook can have different bytes
and no differences in this report. No shared-formula expansion, dependency graph,
external-reference access, macro execution or recalculation occurs. This is not
a visual diff, whole-file fidelity audit, print-ready gate, safe-content verdict,
delivery record or customer acceptance.

## API and bounds

```mbt nocheck
let result = @xlsx.compare_workbooks(original_package, copy_package)
let json = result.to_json()
```

Open both packages with the existing archive policy first. The API accepts real
OPC packages and returns independent typed result structures without modifying
either package. `WorkbookComparison::to_json` is the stable report projection.
Other hosts can display the typed `SheetDifference` and `CellDifference` arrays
without JSON. No new dependency or private companion is needed.

Per workbook: at most 100 sheets, 100,000 explicit cells, 10,000 merged ranges and
4,000,000 counted UTF-16 units. The text budget includes cell values, formula
expressions/attributes and the sheet name per cell, including expanded shared
strings. A comparison may therefore contain up to 200,000 changed cells when
inputs are disjoint. The existing XML parser bounds also apply. Empty sheet
names, duplicate exact names/relationships/coordinates, aliased worksheet parts,
conflicting cell payloads, unsupported cell types, invalid coordinates and
ambiguous structural containers refuse the comparison rather than return partial
changes. Other unsupported content remains outside the view, not certified.

The CLI limits each compressed file and each compressed/uncompressed entry to
8 MiB, and each package to 16 MiB uncompressed total. Existing ZIP/OPC path, CRC,
entry-count, ratio and XML limits apply before comparison. Processing and output
are in memory; these ceilings are not a production memory/performance SLA.

## Focused evidence

`xlsx/compare_test.mbt` exercises formula/cache/metadata independence, source
immutability, scalar types, Unicode, shared-string reindexing, blank distinctions,
sheet and merge changes, epochs, JSON option projection, identity refusals, sparse
coordinates, the 100,000-cell boundary and expanded-text bounds.
`tests/workbook_compare_cli.py` exercises real XLSX bytes, readable/JSON/default
modes, style-only/identical/reverse/epoch comparisons and failed input paths.
Retained fixtures were produced with installed XlsxWriter 3.2.9; openpyxl 3.1.5
independently reopens values, formulas and caches. Caches were explicitly supplied
as synthetic fixture values, not calculated. See fixture `PROVENANCE.json` for
producer identity and hashes. No real-customer or Office visual acceptance is
claimed, and cumulative portfolio qualification remains R50.
