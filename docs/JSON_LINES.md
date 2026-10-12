# Analyze order lines from a nested JSON export

An order or invoice API often exports one parent record with several line items.
Import those lines into a typed table, carrying selected order/customer fields
alongside each item. Then use the existing query recipe to filter, sort and
project the useful rows, and create a fresh CSV, JSON or XLSX. This is an offline
value-dataset adapter. It does not contact a provider or alter the source JSON.

## Practical example

The synthetic fixture under `kit/json-lines/` has three orders, four line items
and an empty second order. Two items share a SKU; neither is silently deduplicated.
The query selects quantity at least two and sorts descending, producing source
positions (parent 3, item 1), (parent 3, item 2), (parent 1, item 2). The source
order number `001`, Unicode, a multiline note, numbers, Booleans and `=1+1` survive
the declared typed output subset.

Build `cmd/json-lines` for JavaScript with the pinned toolchain, private HOME/XDG,
frozen dependencies and an absolute external target directory. Run:

```sh
node /absolute/build/js/debug/build/cmd/json-lines/json-lines.js \
  kit/json-lines/orders.json kit/json-lines/mapping.json \
  kit/json-lines/query.json xlsx /absolute/fresh/order-lines.xlsx
```

Use `-` instead of a query file to export every expanded line, or `csv` / `json`
for those formats. The final path must be fresh. The CLI exclusively creates a
mode-0600 file after all validation and serialization, and compares its exact
readback. It refuses existing destinations, including the source or mapping.
A failed write/readback may leave a fresh, unverified file; retry to another
fresh destination. No deletion or overwrite is performed.

Standard output contains a report, not dataset bytes. Retain that report beside
the output. It includes exact source/mapping/output SHA-256, mapping and query,
parent and expanded/matched/output counts, output columns, skipped empty-parent
positions and original parent/item positions for every output row. Query sorting,
limiting or dropping locator columns does not remove the report's locators.
Digests identify the bytes read during this invocation, not the source path's
later state, authenticity, completeness or factual correctness.

## Explicit mapping

```json
{
  "version": 1,
  "record_path": ["orders"],
  "items_path": ["lines"],
  "parent_fields": [{"name":"order","path":["id"],"required":true}],
  "item_fields": [
    {"name":"sku","path":["sku"],"required":true},
    {"name":"qty","path":["qty"]},
    {"name":"note","path":["note"],"nulls":"empty"}
  ],
  "empty_items": "skip"
}
```

All six top-level keys are required and unknown keys fail. Only version 1 and
empty_items=`skip` are supported. `record_path` starts at the document; `[]`
selects a top-level parent array. `items_path` is a nonempty path relative to
each parent, selecting exactly one child-object array. Parent fields are relative
to the parent; item fields are relative to each child. Every path traverses exact,
case-sensitive object keys. Dots, slashes, numeric strings and empty-string keys
are literal keys; no array indices, wildcards, recursion or schema inference.

Columns are `_parent_row`, `_item_row`, parent fields in mapping order, then item
fields in mapping order. The locators are one-based positions in the selected
parent array and that parent's child array. They are source/mapping-local, not
business keys or physical line numbers. Parent order and child order are retained.
Repeated parents, repeated business identifiers and duplicate item objects all
remain separate rows. The shared JSON parser keeps the final value for duplicate
object keys; no duplicate-key or original lexical-form preservation is claimed.

The parent array and all child arrays must exist and contain objects. An empty
parent array produces headers with no rows. An empty child array produces no
line, and its parent position is returned in empty_parent_rows. Missing, null or
non-array child lists fail, as do non-object items. Selected parent fields are
validated even for an empty child array. A malformed later item or one that a
query would discard still fails the entire import; no partial output is written.

Field options reuse [JSON record](JSON_RECORDS.md) semantics: `required` defaults
to false and `nulls` to `reject`. A missing optional key becomes Empty. A present
non-object intermediate path fails. Null conversion must explicitly choose
`empty` (Empty) or `literal` (text `null`); required=true concerns presence, so it
still allows those explicit null conversions. Strings, finite numbers and
Booleans remain typed scalars. Selected arrays/objects fail. Unselected fields
are ignored. Empty and missing are not distinct in the existing cell model.

## Library use and bounds

`parse_json_line_spec(mapping_text)` returns `JsonLineSpec`.
`parse_json_lines(input_text, spec)` returns `JsonLineTable { table, parent_count,
empty_parent_rows }`. Call `table.query(recipe)` and use its one-based source_rows
to recover the original locator columns if the query projects them out.
The library has no filesystem effects; arrays for different result rows are
separate, including repeated parent cells. Directly constructed specs are also
validated. Errors report the parent position, optional child position, selected
column and reason where applicable.

Limits: input 4,000,000 UTF-16 units; mapping 65,536 units; paths at most 16 keys,
keys and field names at most 256 units; zero or more parent fields and at least
one item field, at most 128 fields combined. Names must be unique, nonblank and
cannot collide with the two locator names. Maximum 10,000 parent records,
10,000 expanded rows and 100,000 cells including headers. Expanded scalar text
is at most 4,000,000 UTF-16 units including headers and repeated parent text
(Boolean values count as four/five units). This bounds parent-text amplification
before serialization. The CLI additionally accepts regular UTF-8 input files up
to 8 MiB and mapping/query files up to 65,536 bytes, with fatal UTF-8 decoding.
No streaming, adversarial memory/CPU guarantee or performance SLA is claimed.

## Output and fidelity limits

JSON omits Empty cells, and an empty JSON array cannot carry a column schema.
CSV loses types and missingness; a spreadsheet application may interpret
formula-looking strings when opening CSV. XLSX creates a simple new value
workbook and keeps formula-looking text as inline text. Existing writer bounds
and character validity rules apply. Numbers use the existing JSON numeric
representation and downstream numeric-query semantics; keep exact monetary
precision and identifiers as strings when required. No calculation, currency or
date conversion is performed.

There is one selected child array per parent, with no Cartesian product, outer
placeholder rows, deeper array expansion, automatic totals or pagination. The
adapter provides no MoonDesk UI, general Office fidelity, render verification,
source completeness, customer acceptance or permission to share. `readback_equal`
means byte readback only; it is not DocumentSession save verification. The focused
CLI harness independently parses CSV/JSON and XLSX ZIP/XML; graphical Office
acceptance and cumulative suite qualification remain outside this delivery.
