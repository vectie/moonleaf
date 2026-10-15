# Cell value and formula editing

MoonLeaf 0.1.38 adds a value editor without changing the existing `edit` text command or document-session text restrictions.

```
moonleaf-preview edit-value SOURCE NAME OUTPUT
```

Standard input is exactly `{ "sheet": "Sheet1", "row": 1, "column": 1, "value_type": "formula", "value": "=SUM(B1:B3)" }`. Coordinates are one based. `value_type` is `text`, `number`, or `formula`; `value` is always a string. Interactive edits accept rows 1–10000, columns 1–256 and at most 32768 value characters. Formula expressions have a 2048 character limit. The output path must not exist.

The JSON receipt has contract `moonleaf.cell-value-edit.v1`, `sheet`, `row`, `column`, `value_type`, and `recalculated_formulas`. Formula edits additionally return `formula`, the stored expression without its leading equals sign.

XLSX edits preserve the target style and unrelated OPC parts, recalculate the completed workbook and write a new copy. Ordinary formula cells may be replaced. Shared, array and data-table formula targets and non-anchor merged cells are rejected. Existing `set_cell_text` and session editing retain their previous semantics. The XLSX APIs `set_cell_formula` and `set_cell_value` return a recalculated package.

CSV/TSV accept text and finite numeric edits. Text retains the existing formula-injection protection. Formula editing and recalculation require XLSX.

```
moonleaf-preview recalculate SOURCE NAME OUTPUT
```

This command takes no standard input and returns `{ "contract": "moonleaf.workbook-recalculate.v1", "recalculated_formulas": 0 }`, with the actual formula count instead of the example zero.

The evaluator supports arithmetic, percentages, same-sheet A1 references, SUM/MIN/MAX ranges, ROUND, AVERAGE and COUNT. MoonLeaf 0.1.39 adds fractional powers through `^` and `POWER(base, exponent)` for editable geometric-growth and discount-rate formulas. AVERAGE/COUNT ignore blank, text and boolean cells in ranges and direct cell references; formula cells are evaluated before counting. Errors, cycles, unsupported functions or external/cross-sheet references stop the operation before output is written. This remains a bounded calculation profile, with 10000 workbook cells, a 200000-step evaluation budget and ranges of at most 10000 cells.

Each preview sheet includes `formula_expressions`: triples `[row, column, expression]` with one-based coordinates and the raw stored expression. Existing `rows` continue to expose cached values.

Formula caches with a finite numeric value and an XLSX numeric result type also appear in `numeric_cells`, so their saved percentage/currency formats can be displayed. Text and boolean formula caches remain excluded even when their stored text resembles a number.

`create-xlsx` and `create-workbook` additionally accept explicit JSON formula cells
`{ "formula": "A2*(B2/A2)^((C2-3)/7)", "cached": 123.4 }`; the cache is optional.
Creation recalculates these formulas using this same evaluator before saving.
Plain JSON strings beginning with `=` remain literal text. See
[multi-sheet creation](../cmd/preview/MULTISHEET.md) for the JSON format and power
precedence.
