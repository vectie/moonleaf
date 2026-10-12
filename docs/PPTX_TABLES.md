# Turn a PowerPoint business table into a usable dataset

R371 adds read-only intake of one ordinary slide table, with exact text, slide
references and physical row numbers, into MoonLeaf's existing query and export
pipeline. A reviewer can take a supplier-cost table out of a deck, filter/sort it,
and produce CSV, JSON or a new literal-text XLSX. This is a derived dataset, not
an edited presentation, renderer, complete-source inventory or visual-fidelity
claim. The earlier presentation outline remains useful for full text/notes review.

## Discover, select and export

```sh
moon --target-dir /absolute/external-build build cmd/pptx-table --target js --frozen --strip -j 1
node /absolute/external-build/js/debug/build/cmd/pptx-table/pptx-table.js inspect kit/pptx-table/suppliers.pptx
node /absolute/external-build/js/debug/build/cmd/pptx-table/pptx-table.js export kit/pptx-table/suppliers.pptx kit/pptx-table/selection.json kit/pptx-table/query.json xlsx /fresh/suppliers.xlsx
```

`inspect SOURCE.pptx` returns `moonleaf.pptx-tables.v1`, the source SHA-256 and
candidate tables in actual presentation order, then XML shape-tree order.
Ordinary tables in groups and hidden slides are included. Candidates identify
`id`, `slide_number`, exact OPC `part`, `shape_id`, `hidden_slide`, `rows`,
`columns`, `first_row`, and `refusal`. A refused candidate has zero rows/columns
and an empty first row; those zeroes are not an assertion that the source table
is empty. A merged table does not prevent a later supported table's intake.
Invalid archive/XML, unsupported root namespaces, rebound standard prefixes or
invalid slide relationships fail the discovery as a whole.

IDs such as `slide:1/table:2` mean one-based presentation position and table
ordinal within the supported shape tree, not slide filename or visual order.
Shape IDs can repeat across slides; the exact source digest, part and table ID
are the selection identity. IDs are not persistent edit targets. Reinspect after
any source byte changes.

The selection JSON requires exactly four properties:

```json
{
  "version": 1,
  "source_sha256": "64-character digest from inspect",
  "table": "slide:1/table:2",
  "header": "first_row"
}
```

`first_row` uses the first physical row as exact unique nonempty column names.
Alternatively, `"header": ["id", "supplier", "amount", "notes"]` retains every
physical row as data with those supplied column names. Width must match; headers
are never trimmed, renamed or deduplicated. Whitespace-only names are nonempty.
Header-only tables validly produce zero data rows. Provide unique JSON properties:
the existing JSON parser resolves duplicate properties to the final value.

`export SOURCE.pptx SELECTION.json QUERY.json|- csv|json|xlsx FRESH_OUTPUT` checks
the source digest, parses the table and applies an optional existing
[version-1 query recipe](QUERY_TABLES.md). `-` skips querying. Numeric comparison
can filter/sort decimal text without changing its spelling or literal text type.
The sample filters amount >= 1000 and sorts descending, yielding suppliers 003
and 001 at physical table rows [4,2], with exact text and blank lines retained.

The JSON success report is `moonleaf.pptx-table-export.v1`. It includes source
and output SHA-256, selection/query, format, row counts, columns, physical
`table_rows` in output order, slide number/part/shape ID/hidden flag, readback
result and limitations. Keep it with the original and output; digests identify
bytes, not authorship, factual truth, permission to share or customer acceptance.

## Text subset and discovery boundaries

- Standard transitional `p:presentation` and `p:sld`, with explicit standard
  `p`, `a` and presentation `r` bindings. Alternative prefixes/strict root
  namespaces are outside this subset. Strict and transitional slide relationship
  type URIs are recognized. Slide targets must be internal package paths.
- Tables must occur directly in ordinary `p:graphicFrame/a:graphic/a:graphicData`
  within the slide shape tree or its `p:grpSp` groups. Graphic data must declare
  the standard DrawingML table URI and contain one table. Chart/SmartArt frames
  are not candidates. Wrapped/AlternateContent tables are not discovered.
- Rectangular unmerged tables with one `a:tblGrid` and physical rows matching its
  width. All merge/span attributes are refused, even explicit span 1/merge false.
  This deliberately avoids silently inventing business records from merged cells.
- Ordinary `a:txBody/a:p/a:r/a:t` text. Runs concatenate, explicit `a:br` becomes
  a newline, paragraphs join with newlines, including blank paragraphs. Tabs and
  whitespace present in text are retained. Empty cells remain empty strings.
- All values remain literal strings, including `001`, `12.50`, `true` and `=1+1`.
  There is no number/date/Boolean/formula inference or recalculation.
- Selected cached fields, hyperlinks, extension lists, unknown content, nested
  text elements, multiple text bodies and inconsistent grids are refused.
  Formatting properties are not rendered: styles, bullets/numbering, layout,
  fonts, visibility inherited from groups/layouts, and Office display rules are
  not interpreted. The hidden flag reports only the slide's own `show` attribute.
- Notes, layouts, masters, other text/shapes, comments, images/OCR, charts, media
  and animation are not imported, fetched or executed. Notes parts are not read,
  so malformed unrelated notes do not prevent a table import. Discovery is not a
  complete source inventory, XSD validation or hostile-document safety analysis.

## Outputs and host boundary

CSV is fully quoted, but spreadsheet applications may still interpret formula-
looking text. XLSX uses explicit inline-string cells and no source formulas;
it creates a new simple `JSON data` sheet rather than copying source formatting,
package parts, hyperlinks or other slides. JSON preserves strings and empties;
a zero-row JSON array loses schema, which stays in the report.

The Node adapter reads a regular file snapshot. It never opens the source for
writing and does not lock it against concurrent changes. All validation/query/
serialization completes before an exclusive mode-0600 `wx` create. Existing
files, source path, hardlinks, symlinks and directories are refused. Output bytes
are read back and compared before a success report. Failed writes/readbacks can
leave partial or unverified fresh files; no automatic deletion/overwrite occurs.
Inspect the error and retry at a fresh destination. Hosts own original retention,
permissions, destination conflicts and delivery/sharing decisions. This workflow
adds no save-as-copy, print-ready, visual-acceptance or MoonDesk UI qualification.

## Library

```mbt nocheck
let candidates = @pptx.read_tables(policy_opened_package)
let imported = @jsontable.extract_pptx(
  policy_opened_package,
  table_id="slide:1/table:2",
  header=@jsontable.FirstSlideTableRow,
)
let queried = imported.table.query(recipe)
let source_rows = queried.source_rows.map(i => imported.source_rows[i - 1])
let output = queried.table.export_xlsx()
```

Library callers bind IDs to their source identity and open under an appropriate
OPC archive policy. APIs have no file/network effects and return owned arrays;
mutating the returned data cannot change the source package.

## Bounds and evidence

Up to 200 slides, 1000 discovered tables and 100000 encountered shape-tree items.
Per table: 1000 physical rows, 128 columns, 100000 cells and 2000000 UTF-16 text
units. Accepted tables together may contain at most 100000 cells and 2000000
text units. Imported headers plus data also have a 2000000-unit cap. OPC/XML
parser bounds apply earlier. The CLI source is at most 8 MiB, selection/query
files at most 64 KiB; package entries at most 8 MiB compressed/uncompressed and
16 MiB total expanded bytes. XLSX export has its own existing 100000-cell and
2000000-text-unit ceilings, including generated headers. Everything is in memory;
no streaming or performance SLA is claimed.

`jsontable/pptx_test.mbt` tests focused library behavior on JS/native.
`tests/pptx_table_cli.py /absolute/build /fresh/evidence` invokes the real Node
CLI and independently inspects retained python-pptx 1.0.2-produced source XML,
relationship order and CSV/JSON/XLSX results. The synthetic business data and
producer generator are committed; tests use the retained bytes without requiring
python-pptx installation or regeneration. No PowerPoint visual rendering,
production host behavior or cumulative historical runtime qualification is claimed.
