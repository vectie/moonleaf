///| Render a normalized, bounded cell-value proof for quote workbooks. This is

///| deliberately not an Excel print-layout emulator; the original workbook bytes

///|
/// remain the delivered artifact. Cached formulas must already be recalculated.
pub fn render_xlsx_proof_pdf(
  document_package : @opc.Package,
  fonts : Array[PdfFontInput],
  default_family~ : String,
) -> PdfDocument raise {
  let workbook = @xlsx.read(document_package)
  guard workbook.warnings.is_empty() else {
    raise Unsupported("spreadsheet parse diagnostics")
  }
  let inspected = @xlsx.inspect(document_package)
  let body = StringBuilder()
  for sheet_index, sheet in workbook.sheets {
    guard sheet.merged_ranges.is_empty() else {
      raise Unsupported("merged quote cells require explicit proof layout")
    }
    let row_count = sheet.cells.fold(init=0, (n, c) => n.max(c.row))
    let col_count = sheet.cells.fold(init=0, (n, c) => n.max(c.column))
    guard row_count <= 1000 && col_count <= 12 && col_count > 0 else {
      raise Unsupported("quote sheet exceeds bounded proof grid")
    }
    if sheet_index > 0 {
      body.write_string("<w:p><w:r><w:br w:type=\"page\"/></w:r></w:p>")
    }
    body.write_string(
      "<w:p><w:r><w:t>\{@xml.escape_text(sheet.name)}</w:t></w:r></w:p><w:tbl><w:tblPr><w:tblBorders>",
    )
    for edge in ["top", "bottom", "left", "right", "insideH", "insideV"] {
      body.write_string("<w:\{edge} w:val=\"single\" w:sz=\"4\"/>")
    }
    body.write_string("</w:tblBorders></w:tblPr><w:tblGrid>")
    for _ in 0..<col_count {
      body.write_string("<w:gridCol w:w=\"\{10400 / col_count}\"/>")
    }
    body.write_string("</w:tblGrid>")
    for row in 1..<=row_count {
      body.write_string("<w:tr>")
      for column in 1..<=col_count {
        let mut value = ""
        for cell in inspected {
          if cell.sheet_name == sheet.name &&
            cell.row == row &&
            cell.column == column {
            guard cell.warnings.is_empty() && cell.display_kind != Unsupported else {
              raise Unsupported("quote cell has unsupported number format")
            }
            if cell.formula is Some(_) && cell.cached_value is None {
              raise Unsupported("uncalculated quote formula")
            }
            value = cell.resolved_text.unwrap_or(
              cell.cached_value.unwrap_or(cell.raw_value.unwrap_or("")),
            )
          }
        }
        body.write_string(
          "<w:tc><w:p><w:r><w:rPr><w:sz w:val=\"20\"/></w:rPr><w:t>\{@xml.escape_text(value)}</w:t></w:r></w:p></w:tc>",
        )
      }
      body.write_string("</w:tr>")
    }
    body.write_string("</w:tbl>")
  }
  body.write_string(
    "<w:sectPr><w:pgSz w:w=\"11906\" w:h=\"16838\"/><w:pgMar w:top=\"720\" w:bottom=\"720\" w:left=\"720\" w:right=\"720\"/></w:sectPr>",
  )
  let xml = "<w:document xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\"><w:body>\{body}</w:body></w:document>"
  render_docx_pdf(
    {
      parts: [
        {
          name: "word/document.xml",
          content: @utf8.encode(xml).to_fixedarray(),
        },
      ],
    },
    fonts,
    default_family~,
  )
}
