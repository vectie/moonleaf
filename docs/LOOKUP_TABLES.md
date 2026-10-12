# Prepare a cross-file lookup table

MoonLeaf can now enrich an order list with customer metadata, add catalog values to line items, or reconcile identifiers against a reference list. This is a library workflow for a document host; it does not add a MoonDesk control.

1. Read JSON/JSONL using `@jsontable.parse(text, jsonl=true)` as appropriate.
2. Read a header-bearing CSV or TSV reference using `@jsontable.parse_delimited(text)` or `delimiter='\t'`. CSV/TSV cells stay text, so identifiers such as `001` remain intact. Either side may come from either parser.
3. Call `source.lookup(reference, source_key="customer", lookup_key="id", columns=["name", "region"], prefix="customer.")`.
4. Review `result.table`, `result.source_rows`, and `result.lookup_rows`. Row identities are one-based data rows in the immediate inputs, excluding the CSV/TSV header. `None` identifies unmatched rows. The default left lookup keeps every source row in original order. `matched_only=true` keeps only matched rows, preserving their order.
5. Export the prepared table with `export_csv()` or `export_xlsx()`. Reopen with the existing CSV/XLSX readers. Original tables are not mutated; result row and column arrays are separate copies.

`columns` names the reference fields to append, in order. All original source columns remain. Prefix defaults to `lookup.`; empty or colliding output names are rejected. Selecting no columns is supported for matching/reconciliation using the row identities.

## Matching rules

Keys are exact, case-sensitive, nonempty text. There is no trimming, number coercion, date parsing, fuzzy matching or locale normalization. `001`, `1`, ` A ` and `A` remain distinct. Numeric/boolean/formula keys are rejected; encode identifiers as JSON strings. Missing or empty source keys are unmatched. Missing/empty reference keys are rejected, as are duplicate reference keys, including duplicates not used by the source. Duplicate source keys are allowed and do not multiply rows.

JSON null and nested values retain the existing table parser's text projection; this API cannot distinguish JSON null from the literal string `null` once projected. Use explicit string identifier fields, not null/nested fields, as keys. This is a unique-key lookup, not a many-to-many database join.

CSV/TSV requires a unique nonempty header and rectangular data rows. Existing CSV parser limits apply. Export retains typed JSON numbers and booleans in XLSX; CSV is text. Existing writer limits apply: 256 columns and 100000 cells. Input parsing, lookup and output are in-memory; no streaming/database-scale claim. It creates a new dataset, not a fidelity-preserving rewrite of a source workbook. Source file access, source digests and save destination remain host responsibilities.

## Runnable synthetic example

`examples/lookup/main.mbt` embeds the matching inputs under `docs/samples/lookup/`. From this module, run:

```
moon run examples/lookup --target wasm
```

The output adds customer name/region to three orders, retains typed amounts internally, and leaves the unknown customer unmatched. With the recovered pinned toolchain, use the round's `run.mbtx` runner and frozen external build directories as documented in its handoff. Tests also reopen XLSX output and prove typed values, leading-zero IDs and Unicode survive.

Mapped [XML records](XML_RECORDS.md) can also supply either side of a lookup.
Use `parse_xml_records` with an explicit mapping; leading-zero keys stay text.
