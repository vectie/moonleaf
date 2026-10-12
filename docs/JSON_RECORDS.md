# Import nested JSON business records

Use MoonLeaf to turn an offline API response or nested JSON export into an explicit,
reviewable flat table. Choose the record array and each field by exact object-key
paths; keep original files for context. This adapter does not contact a provider,
follow pagination, recursively flatten objects, explode arrays, or infer a schema.

## Run the synthetic example

From the patched MoonLeaf checkout, with the pinned compiler and private frozen
dependencies, build the JS adapter and existing preview tool:

```
moon build cmd/json_records cmd/preview --target js --frozen --strip -j 1 --target-dir /absolute/external-build
node /absolute/external-build/js/debug/build/cmd/json_records/json_records.js kit/json-records/mapping.json kit/json-records/envelope.json json > /fresh/path/projected.json
```

Replace the last argument with csv or xlsx for those output formats. Review the
saved table with `node /absolute/external-build/js/debug/build/cmd/preview/preview.js
/fresh/path/projected.json`. All examples are synthetic. Actual three-format
outputs, parser reopen results, XLSX worksheet XML, ZIP check and original SHA256
are in `kit/json-records/` inside the checkout; this delivery also includes the
same files in `accepted/` alongside this guide.

The example selects response.items and maps id, customer.name, totals.net,
active and note. A literal `=1+1` remains typed inline text in XLSX. A leading-zero
identifier stays text, a number stays Number, and a Boolean stays Boolean.

## Mapping contract

```
{
  "record_path": ["response", "items"],
  "fields": [
    {"name":"id", "path":["id"], "required":true},
    {"name":"customer", "path":["customer","name"]},
    {"name":"note", "path":["note"], "nulls":"empty"}
  ]
}
```

- record_path starts at the JSON document; [] selects a top-level array. It must
  resolve to one existing array whose every element is an object. An empty
  selected array is supported and preserves the chosen columns in memory/CSV/XLSX.
- Every field path is nonempty and relative to each selected record. Keys are
  literal and case-sensitive; dots, slashes, numeric strings and empty-string
  keys have no special meaning. No array indexing, wildcard or normalization.
- Column order is mapping order, preceded by `_record_row`, the one-based original
  index in the selected array. It is a locator within this input, not a physical
  line number, source identity, digest or authenticity claim. Retain the input,
  mapping and their digests when passing a table into another workflow.
- Missing keys anywhere in an otherwise traversable path produce Empty unless
  required=true, in which case the entire intake fails. required defaults false.
  A present intermediate null/scalar/array fails even for an optional field.
- Selected strings, finite numbers and Booleans use the existing table scalar
  model. Selected objects or arrays fail instead of becoming unexplained text.
  Unselected data is ignored. JSON null defaults to refusal. Explicit nulls=empty
  converts to Empty (same as a missing field); nulls=literal converts to text
  "null" (same as that literal string). required=true still allows an explicitly
  chosen null conversion because the key is present. No null-preserving cell type.
- Unknown mapping options, duplicate/blank column names and `_record_row` field
  names fail. Distinct columns may intentionally select the same path.
- The shared JSON parser's numeric precision/normalization and object-key parsing
  semantics apply (duplicate object keys keep the final value); this is not a lossless original JSON codec. Keep large exact
  identifiers or monetary precision as source strings. It does not compute totals,
  fetch subsequent pages or prove that an export contains all business records.

## Library integration

```
let spec = @jsontable.parse_json_record_spec(mapping_text)
let table = @jsontable.parse_json_records(input_text, spec)
let json = table.export_json(omit_empty=true)
```

Direct callers can construct JsonRecordSpec with `records_path` (the JSON mapping
key is `record_path`) and JsonRecordField values (name, path, required, nulls).
JsonRecordNulls variants are RejectNull, EmptyNull, LiteralNull. Structured errors
identify data row/column/reason for field failures. Result tables are fresh values;
no filesystem effects are performed by this library adapter. Existing query,
lookup, summary and consolidation workflows can consume the resulting Table.

## Boundaries and output caveats

Library limits: input 4,000,000 UTF-16 code units; mapping 65,536 units; paths at
most 16 keys of at most 256 units each; 1–128 fields; names at most 256 units;
10,000 selected records; 100,000 output cells including header and `_record_row`.
CLI additionally requires regular UTF-8 files up to 8 MiB each, with fatal UTF-8
decoding; no stdin. These are bounded in-memory adapters, not streaming or an
adversarial memory/CPU guarantee. JSON parsing still processes unselected data.

Validation and serialization finish before stdout is written. Errors return
nonzero with no dataset output. Shell redirection itself can truncate a file
before execution; choose a fresh destination distinct from both input and mapping,
and check exit status. Inputs are opened read-only; there is no save-to-source.

JSON output omits Empty fields, so all-missing columns and empty-table schema are
lost on JSON reimport. Numeric representation may normalize. CSV loses types and
missingness; formula-looking text is unchanged and a spreadsheet app might execute
it. Prefer typed XLSX for untrusted text. No formulas, recalculation, Office-wide
fidelity, native GUI acceptance, host save verification, delivery or customer
approval is claimed. Parser reopen evidence is limited to the synthetic fixtures.

## Reproduce acceptance

```
moon test jsontable --target js --frozen --strip -j 1 --target-dir /absolute/external-build
moon test jsontable --target native --frozen --strip -j 1 --target-dir /absolute/external-build
moon run tests/json_records_cli.mbtx --target js --frozen --strip -j 1 --target-dir /absolute/external-build -- /absolute/external-build/js/debug/build/cmd/json_records/json_records.js /absolute/external-build/js/debug/build/cmd/preview/preview.js /absolute/fresh-evidence
```

Use private HOME and XDG paths, the pinned recovery MOON_HOME/PATH,
MOON_DEP_CACHE=off and MOON_BUILD_CACHE=off. Serialize native work under the shared
recovery native-build.lock; use `--strip -j 1`. The verifier requires Node and
unzip. It creates its fresh output directory, compares all projected rows across
all three reopened outputs, checks ZIP/inline text and original hashes, exercises
invalid UTF-8, file/row/size limits and mapping/shape/null refusals, then retries.

For a selected child-object array with parent context, use the separate
[JSON line-item adapter](JSON_LINES.md). The original record mapping above
remains unchanged.
