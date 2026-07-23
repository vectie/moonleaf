# WP06 XLSX problem/fix ledger

## Implicit cell coordinates during editing

- **Symptom:** Editing a row containing legal `<c>` elements without `r` could append a duplicate cell or place the edit after later cells.
- **Root cause:** The editor treated an omitted cell reference as an unknown column, although SpreadsheetML defines it from document order.
- **Fix:** Track the preceding resolved column and assign each implicit cell `previous + 1` while searching/inserting. Existing cell attributes, including style, remain preserved by the replacement path.
- **Failed no-op attempt:** The prior turn added the same WP06 comment to five existing tests; those comment-only changes were removed because they supplied no regression coverage.
- **Real test evidence:** Added `set_cell_text edits implicit prefixed cell without duplicating it`, using a namespace-prefixed worksheet with two omitted `r` attributes followed by explicit `D1`. It verifies one logical B1 after editing, column order `[1, 2, 4]`, namespace/prefix validity, style `9` preservation, and the saved package after reopening. The assertion reads `xl/worksheets/sheet1.xml` through the public `Package::text` accessor (the stored content is already `FixedArray[Byte]`).
- **Validation evidence:** `moon fmt` completed successfully; `moon check --target all` completed 14 tasks for each configured target with no diagnostics; `moon test --target all` passed all 24 tests on wasm, wasm-gc, JavaScript, and native (96 target-test executions total, 0 failures).
- **Preservation:** Explicit references retain precedence; non-cell children and existing row/cell ordering are copied unchanged.
- **Residual risk:** Implicit row coordinates, merged-anchor enforcement, typed setters, recalculation metadata, styles/dates/layout, hyperlinks, and lazy range reads still require production implementation and realistic fixtures.
