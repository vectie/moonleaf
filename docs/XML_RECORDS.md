# Import XML business records

Turn a supplier catalog or order export into a table for matching identifiers,
grouped summaries, CSV interchange or an XLSX review copy. This is a MoonLeaf
library and compiled Node CLI workflow. It does not add XML auto-detection to
`@moonleaf.open`, a MoonDesk control, or XML editing/round-trip fidelity.

## Run the included catalog

From the MoonLeaf module root, with its normal dependencies installed:

```
moon build cmd/xml_records cmd/summarize cmd/preview --target js
node _build/js/debug/build/cmd/xml_records/xml_records.js docs/samples/xml-records/catalog.mapping.json json < docs/samples/xml-records/supplier-catalog.xml > catalog.json
node _build/js/debug/build/cmd/xml_records/xml_records.js docs/samples/xml-records/catalog.mapping.json csv < docs/samples/xml-records/supplier-catalog.xml > catalog.csv
node _build/js/debug/build/cmd/xml_records/xml_records.js docs/samples/xml-records/catalog.mapping.json xlsx < docs/samples/xml-records/supplier-catalog.xml > catalog.xlsx
node _build/js/debug/build/cmd/summarize/summarize.js json docs/samples/xml-records/supplier-summary.json json < catalog.json > supplier-summary.json
node _build/js/debug/build/cmd/preview/preview.js catalog.xlsx catalog.xlsx
```

Use the corresponding external build root in place of `_build` when supplying
`--target-dir`. The verification handoff records the exact pinned/frozen commands.
Choose fresh destinations: shell `>` redirection can truncate a pre-existing
file even when intake fails. The CLI itself reads only the mapping and stdin;
it emits the completed result to stdout and errors to stderr with nonzero exit.
It never opens a source for writing or starts a network request.

All sample data is synthetic. The output contains three products, exact SKU
strings `001`–`003`, UTF-8 names, prices such as `12.50`, and optional barcodes.
The existing summary operator reports N01: 2 products / 34 units; N02: 1 product /
6 units. `orders.xml` and `orders.mapping.json` provide a second reusable input.

## Write a mapping

```
{
  "record_path": ["{urn:moonleaf:catalog}catalog", "{urn:moonleaf:catalog}item"],
  "fields": [
    {"name": "sku", "path": [], "attribute": "sku"},
    {"name": "name", "path": ["{urn:moonleaf:catalog}name"]},
    {"name": "currency", "path": ["{urn:moonleaf:catalog}price"], "attribute": "currency"},
    {"name": "tags", "path": ["{urn:moonleaf:catalog}tag"], "repeated": "join", "separator": " | "}
  ]
}
```

- `record_path` is a nonempty array starting with the document root. Every next
  name selects direct children. A root mismatch is an error; an otherwise valid
  path with zero records returns a zero-row table with the specified columns.
- Field `path` is relative to each record. `[]` selects the record itself. Omit
  `attribute` to select leaf text, or supply an attribute name to select its value.
  `name` becomes the output column name. Names must be unique and nonblank.
- A plain name matches **no namespace**. `{URI}local` matches the namespace URI,
  regardless of prefixes chosen by the producer. Default namespaces apply to
  elements, not unprefixed attributes. Nested namespace declarations/rebindings,
  default-namespace resets and `xml:lang` are supported. Namespace URIs are exact
  strings, never fetched; braces and whitespace in URI values are outside this
  subset. Undeclared/reserved prefixes and duplicate expanded attributes fail.
- Missing children/attributes produce `Empty`. Present empty text or an empty
  attribute produces `Text("")`. Present values stay text: `001`, `12.50`, `false`,
  `null`, dates and formula-shaped strings are never inferred as other types.
- Leaf text combines text and CDATA around comments. Selecting an element with
  child elements for its text fails, preventing accidental mixed-content loss.
  Select its nested leaf explicitly, e.g. `["address", "city"]`.
- Repeated matching elements fail by default (`"repeated": "reject"`). Explicit
  `"join"` requires `separator`; it joins values in document order. Missing
  attributes occupy empty positions when at least one value is present; if all
  are missing, the cell is `Empty`. Joining deliberately collapses structure and
  cannot reconstruct the original repeated values when delimiters occur in data.
- Paths are not XPath. No `//`, wildcards, predicates, indexes, parent steps,
  automatic namespace guessing, type inference or flattening is performed.
  Unknown mapping keys and repeated policies fail. A mapping is required.

## Use tables directly

```
let catalog = @jsontable.parse_xml_records(xml, @jsontable.parse_xml_spec(mapping))
let orders = @jsontable.parse_xml_records(order_xml, order_spec)
let enriched = orders.lookup(catalog, source_key="sku", lookup_key="sku",
  columns=["name", "price"], prefix="catalog.")
let totals = orders.summarize(group_by=["sku"],
  measures=[{ name: "units", operation: @jsontable.Sum("quantity") }])
let copy = enriched.table.export_xlsx()
```

The adapter returns the existing `jsontable.Table`; `workbook()`, exact-key
`lookup`, `summarize`, and the CSV/XLSX/JSON exports operate normally. Explicit
numeric summary measures parse the selected text values using existing finite
JSON-number rules. This does not create a decimal accounting model.

The XML CLI's JSON format uses `table.export_json(omit_empty=true)`: missing
properties are omitted and empty strings remain `""`. This lets the existing
JSON parser recover missing cells when a column is present elsewhere in the
array. JSON object arrays do not carry the schema of an entirely missing column
or a zero-row table; keep the mapping/XLSX when that schema matters. The ordinary
`export_json()` default still emits `null` for `Empty`; existing null-to-text
reimport behavior is unchanged. Column order on JSON reimport is first appearance,
so reuse the mapping's field list if exact column order must be retained.

XLSX stores present values as literal inline strings and missing values as blank
cells, with the normal `JSON data` sheet name. CSV quotes every field but collapses
missing and empty to the same blank text; consumer spreadsheet applications may
coerce IDs or execute formula-shaped CSV text. Prefer XLSX or JSON for preserving
identifiers and literal strings. No input XML structure is written back.

## Supported XML and resource limits

UTF-8 XML 1.0, optionally with a BOM and initial XML declaration, is supported.
Comments, CDATA, the five predefined entities and valid numeric character
references are supported. XML line endings become LF; literal tab/newline
whitespace in attributes becomes spaces. Character references retain the
referenced whitespace. Other whitespace is preserved without trimming.

DTD/entity declarations and all other processing instructions are rejected.
There is no XInclude, schema validation, external entity resolution, network
fetch, arbitrary XML transformation or streaming. Malformed structure, invalid
characters, invalid comments, missing attribute separators, unknown entities and
namespace errors fail before any table is returned. The shared XML DOM parser is
unchanged; intake adds stricter lexical and namespace validation for this subset.

Fixed bounds, checked before or during parsing/projection:

- XML: 1,000,000 UTF-16 units; depth 32; 50,000 element/text nodes; 64 attributes
  per element (including namespace declarations)
- JSON mapping: 65,536 UTF-16 units; 1–128 fields; at most 16 names per path;
  512 units per selector; 256 per column name or join separator
- Table: 10,000 records; 100,000 cells including headers; 65,536 units per field;
  2,000,000 total output text units including headers
- CLI reads at most 4,000,000 XML bytes and 262,144 mapping bytes and rejects
  malformed UTF-8. Library limits still apply after decoding.

Bounds are not a performance or arbitrary-producer qualification. CSV's existing
reader has a stricter 10,000-total-row limit (including its header), so the largest
10,000-record XML table cannot be reopened through that CSV reader. Existing XLSX
writer limits apply. No browser/Office visual acceptance or new host integration
is asserted.

## Tests

```
moon test jsontable --target js
moon test jsontable --target native
MOONLEAF_BUILD_ROOT=/absolute/build-root python3 tests/xml_records_cli_test.py
```

The Python standard-library product tests independently read CSV/JSON and
ZIP/worksheet XML, then reopen XLSX through the existing compiled preview CLI.
Library tests exercise namespace scope, missing/empty cells, exact IDs,
entity/Unicode text, repeat policies, lookup/summary reuse, invalid XML, bounds,
and existing CSV/XLSX readers. They use synthetic data only.
