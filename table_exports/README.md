# In-memory table exports

MoonLeaf 0.1.37 exposes `export_json(raw: String) -> String` from
`vectie/moonleaf/table_exports`. It reuses `csv.create`, `xlsx.create` and
`xlsx.create_workbook`; CSV creation is shared with the preview CLI. The
writers, ZIP codec and base64 encoder are MoonBit code.

The browser bridge in `cmd/browser_exports` publishes
`globalThis.MoonLeafBrowserExports.export_json`. Its only JavaScript FFI
publishes the compiled MoonBit function. Runtime export needs no filesystem,
network, Node modules or native FFI.

```json
{
  "format": "all",
  "workbook_name": "dashboard_views.xlsx",
  "sheets": [
    {"name": "Details", "basename": "dashboard", "rows": [["Name", "Close"], ["Example", 100]]},
    {"name": "Trend", "basename": "trend", "rows": [["Date", "Value"], ["2026-09-30", 100]]}
  ]
}
```

Formats are all/csv/xlsx/workbook. The all format returns a CSV and XLSX for
each sheet and, when workbook_name is supplied, the combined workbook.
The workbook format requires workbook_name and returns only that workbook.
Each sheet basename contains only ASCII letters, digits, hyphens or
underscores; it is a download filename prefix, not a path. The optional
workbook filename uses the same prefix rule and an `.xlsx` suffix.

The response is a JSON string:

```json
{
  "contract": "moonleaf.browser-table-exports.v1",
  "version": "0.1.37",
  "files": [{"name":"dashboard.csv","mime":"text/csv;charset=utf-8","bytes":42,"base64":"...","writer":"moonleaf-moonbit"}],
  "error": null
}
```

The example byte count is illustrative. On any error, files is empty and
error contains a message. Bounds are 2 MiB of input JSON, 1–20 distinct
sheets, 10,000 rows per sheet, 256 columns per row, 100,000 cells and
2,000,000 text characters across tables, and 2 MiB per output file. Text,
finite numbers, booleans and nulls are supported. Strings remain literal in
XLSX; CSV protects strings that a consumer might interpret as formulas.

Compile the browser entry with `moon build --target js --release
cmd/browser_exports`. The local build used Moon compiler
0.1.20260920 (914d7da), producing 698,840 bytes before host embedding. The
Moonfish artifact is `moonleaf_browser_exports.generated.js`.

The portable dashboard should construct fresh tables from its current view
controls at download time, call this bridge, and turn the returned bytes
into download blobs. It must not fall back to export-time table files after
filters, ranking or trend controls change.
