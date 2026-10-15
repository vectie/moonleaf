# Large research workbook creation — 0.1.46

MoonFish's actual October 14 public-fund collection contains 6,315 table rows and 31,575 primitive cells. Its cell text contains 3,111,843 UTF-16 units; the creation request contains 3,485,242 UTF-16 units. The largest individual cell is 707 units.

The previous CLI JSON ceiling of 2,097,152 units and XLSX cell-text ceiling of 2,000,000 units rejected that legitimate collection. Version 0.1.46 supports 8,388,608 UTF-16 units of input JSON and total workbook cell text. Row, cell and worksheet dimensions retain the existing bounds. Individual text cells respect Excel's 32,767-character ceiling. Complete source cells remain intact; this change does not truncate or summarize the data.

XLSX creation now appends escaped values and cell tags directly to the worksheet builder. It avoids intermediate escaped-text strings, full cell XML strings and repeated replacement passes for every cell. XML validity and carriage-return preservation remain in the MoonBit writer. The original OPC ZIP implementation remains shared with the other Office formats.

Code inspection found inline strings and a growing worksheet builder, not a quadratic shared-string lookup. Native IO already reads 8 KiB chunks. The observed timeout cannot establish which stage consumed the deadline; the directly confirmed feature blocker was the workbook capacity. No timeout was increased and no performance claim is based on a benchmark.

Scoped native/JS compilation, interfaces and formatting were used. No tests, benchmarks, synthetic workbooks, model runs or browser validation were performed.

## CSV creation and reading — 0.1.47

The same real fund collection also exceeded CSV's previous 2 MiB export ceiling and 2 Mi UTF-16 reader ceiling. CSV export and edited-copy bytes now support 8 MiB; CSV parsing, table editing and spreadsheet preview support 8 Mi UTF-16 units. Existing row and cell dimensions remain consistent.

CSV serialization writes unchanged spans in bulk and doubles only embedded quotation marks. Parsing similarly appends complete quoted or unquoted spans instead of allocating a complete character array and appending each character individually. BOM, quoted fields, CRLF, escaped quotes, multiline values and existing literal-formula protection retain their established representations.

Creation does not reparse the entire newly written CSV. The original writer owns RFC 4180 quoting and quote escaping; creation still checks row, column, cell, text and encoded-output capacity. Complete original field values remain in the output. Edited external CSV copies continue using their existing parse comparison. No transport timeout changes or measured performance claims are part of this fix.
