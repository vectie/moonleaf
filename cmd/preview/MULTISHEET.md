# Create a workbook with multiple sheets

MoonLeaf 0.1.36 adds `xlsx.create_workbook` and the native/JS preview CLI's
`create-workbook` operation. Both reuse the existing single-sheet cell writer
and OPC package writer; no second XLSX serializer is introduced.

Library signature:

```mbt
pub fn create_workbook(
  sheets : Array[(String, Array[Array[@scene.CellValue]])],
) -> FixedArray[Byte] raise XlsxError
```

CLI invocation:

```text
moonleaf-preview create-workbook OUTPUT.xlsx
```

The stdin JSON body is:

```json
{
  "sheets": [
    {"name": "Details", "rows": [["Name", "Value"], ["Example", 123.4]]},
    {"name": "Trend", "rows": [["Date", "Close"], ["2026-09-30", 100]]}
  ]
}
```

There must be 1–20 sheets. Sheet names are distinct ignoring case and satisfy
the existing XLSX sheet-name validation. Each sheet has at most 10,001 rows
and 256 columns per row; the whole workbook shares the 100,000-cell and
2,000,000-character budgets. The CLI stdin body is limited to 2 MiB.
Strings are literal text, JSON numbers remain numeric cells, JSON booleans
remain boolean cells, and nulls are empty cells. The CLI reopens the generated package to verify its sheet count
before writing a new output file with the existing exclusive writer.

The first row of each sheet uses the existing header style. Creation
preserves sheet order. Existing single-sheet `create-xlsx` and `create-csv`
commands keep their interfaces and behavior.

The global-index workflow in Moonfish exercised four actual computed tables
through this command. Native MoonLeaf reopened all four sheets with their
numeric cells and dimensions preserved: 7×11 detail, 64×3 trend, 7×4 ranking,
and 11×11 correlation. Native source/build verification was focused on these
packages; JS/Linux runtime binaries were not rebuilt for that local rollout.

## Explicit formula cells (0.1.39)

Both `create-workbook` and `create-xlsx` accept JSON cells of the form
`{"formula":"A2*(B2/A2)^((C2-3)/7)","cached":123.4}`. `cached` is an optional
finite number. A leading `=` in `formula` is optional. Ordinary JSON strings,
including strings beginning with `=`, remain literal text.

Creation writes the existing MoonLeaf formula cell and recalculates its numeric
cache through the original MoonBit `xlsx.recalculate` engine before saving.
The provided cache is therefore a creation hint and is replaced by the computed
value. Existing cell editing and explicit recalculation use the same evaluator.

The local same-sheet formula profile now supports `^` and `POWER(base,exponent)`
with fractional exponents, alongside arithmetic, percentages, A1 references,
SUM, ROUND, MIN, MAX, AVERAGE and COUNT. Powers bind before multiplication and
division; unary negation and percentages bind before powers. Repeated powers
are evaluated left to right, following
[Excel's documented operator order](https://support.microsoft.com/en-us/excel/calculation-operators-and-precedence-in-excel).
Parentheses specify alternative grouping. Negative bases with fractional powers,
zero bases with nonpositive exponents, and nonfinite results are unavailable.
Named variables and references to other sheets remain outside this profile.

This supports editable discounted-profit workbooks such as `(1+A2)^B2` and
geometric bridges such as `E3*(F3/E3)^((A4-3)/7)` without a separate JavaScript
formula implementation.
