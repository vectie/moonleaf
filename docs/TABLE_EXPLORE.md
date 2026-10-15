# Explore a saved spreadsheet

MoonLeaf's preview bridge can read CSV, TSV and an exact named XLSX worksheet,
filter and sort its saved rows, summarize groups, and export a copy. MoonDesk
and PaiWork use the same Leaf spreadsheet readers and `jsontable` exports.
The source file stays unchanged.

```sh
node preview.js table-explore SOURCE DISPLAY_NAME [OUTPUT] < request.json
```

`DISPLAY_NAME` supplies the file extension even when `SOURCE` is stored under an
opaque name. `OUTPUT` is optional and must not exist; the bridge creates it with
private permissions. Without `OUTPUT`, the command only emits a JSON report.

Example request:

```json
{
  "sheet": "Revenue",
  "text_column": "Region",
  "contains": "east",
  "number_column": "Amount",
  "min": 10,
  "max": 100,
  "sort": "Amount",
  "sort_type": "number",
  "direction": "desc",
  "group": "Region",
  "sum": "Amount",
  "offset": 0,
  "limit": 200,
  "export_format": "xlsx",
  "export_target": "summary"
}
```

All fields are optional. Columns accept a zero-based numeric index or an exact
header. `sheet` defaults to the first worksheet. Empty or repeated headers
receive unique labels such as `Column 2` and `Region (2)`. Text filtering is
case-insensitive; text and numeric filters combine with AND. Numeric bounds are
inclusive finite JSON numbers. Numeric filters exclude empty or nonnumeric
cells, and numeric sort always places those cells last. Sort ties preserve
worksheet row order.

The report has contract `moonleaf.table-explore.v1`, worksheet names, selected
sheet, columns, text rows, original one-based worksheet `row_indices`,
`source_rows`, `matched_rows`, page offset/limit, and `truncated`. It also returns
`summary` (`columns`, text `rows`, `total_rows`, `truncated`) and `totals`
(`rows`, `numeric_values`, `sum`, `overflow`). A missing sum is JSON null. Group
summary skips nonnumeric amounts and preserves first group appearance after
sorting. XLSX formulas use their saved cached value without recalculation;
formulas without a cache are empty.

Reports return up to 1000 rows and 1000 summary groups, within a 2 MiB JSON
limit. Input worksheet bounds are 100000 rows, 1000 columns and 1000000 cells.
Exports contain every matching row or every summary group, regardless of report
pagination. `export_format` is `csv` (default) or `xlsx`; `export_target` is `rows`
(default) or `summary`. CSV is UTF-8 with BOM and limited to the Leaf reader's
2 MiB bound. XLSX exports retain literal text and typed numeric summary totals.
The export receipt reports format, target, dimensions and bytes.
