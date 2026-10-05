///|
fn create_part(name : String, content : String) -> @opc.Part {
  { name, content: @utf8.encode(content).to_fixedarray(), }
}

///|
fn created_cell(
  value : @scene.CellValue,
  reference : String,
  header : Bool,
) -> String {
  let style = if header { "1" } else { "0" }
  match value {
    Empty => "<c r=\"\{reference}\" s=\"\{style}\"/>"
    Number(number) =>
      "<c r=\"\{reference}\" s=\"\{style}\"><v>\{@xml.escape_text(number)}</v></c>"
    Boolean(flag) =>
      "<c r=\"\{reference}\" t=\"b\" s=\"\{style}\"><v>\{if flag { "1" } else { "0" }}</v></c>"
    Text(text) | Error(text) =>
      "<c r=\"\{reference}\" t=\"inlineStr\" s=\"\{style}\"><is><t xml:space=\"preserve\">\{@xml.escape_text(text)}</t></is></c>"
    Formula(expression~, cached~) => {
      let cache = match cached {
        Some(value) => "<v>\{@xml.escape_text(value)}</v>"
        None => ""
      }
      "<c r=\"\{reference}\" s=\"\{style}\"><f>\{@xml.escape_text(expression)}</f>\{cache}</c>"
    }
  }
}

///|
/// Create a single-sheet XLSX using MoonLeaf's OPC ZIP writer.
/// Strings are stored as literal inline strings, including text beginning with '='.
pub fn create(
  rows : Array[Array[@scene.CellValue]],
  sheet_name? : String = "研究证据",
) -> FixedArray[Byte] raise XlsxError {
  if rows.length() > 10_001 || sheet_name == "" || sheet_name.length() > 31 {
    raise InvalidWorkbook("invalid XLSX dimensions or sheet name")
  }
  for forbidden in ['[', ']', ':', '*', '?', '/', '\\'] {
    if sheet_name.contains_char(forbidden) {
      raise InvalidWorkbook("invalid XLSX sheet name")
    }
  }
  let sheet = StringBuilder()
  sheet.write_string(
    "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>",
  )
  sheet.write_string(
    "<worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\"><sheetData>",
  )
  let mut total_cells = 0
  let mut total_text = 0
  for row_index, row in rows {
    if row.length() > 256 {
      raise InvalidWorkbook("XLSX row exceeds 256 cells")
    }
    total_cells += row.length()
    if total_cells > 100_000 {
      raise InvalidWorkbook("XLSX exceeds 100000 cells")
    }
    sheet.write_string("<row r=\"\{row_index + 1}\">")
    for column_index, value in row {
      total_text += match value {
        Empty | Boolean(_) => 0
        Text(text) | Number(text) | Error(text) => text.length()
        Formula(expression~, cached~) =>
          expression.length() + cached.unwrap_or("").length()
      }
      if total_text > 2_000_000 {
        raise InvalidWorkbook("XLSX exceeds 2 MB of cell text")
      }
      sheet.write_string(
        created_cell(
          value,
          cell_reference(row_index + 1, column_index + 1),
          row_index == 0,
        ),
      )
    }
    sheet.write_string("</row>")
  }
  sheet.write_string("</sheetData></worksheet>")
  let parts = [
    create_part(
      "[Content_Types].xml", "<?xml version=\"1.0\" encoding=\"UTF-8\"?><Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Default Extension=\"xml\" ContentType=\"application/xml\"/><Override PartName=\"/xl/workbook.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml\"/><Override PartName=\"/xl/worksheets/sheet1.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/><Override PartName=\"/xl/styles.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml\"/></Types>",
    ),
    create_part(
      "_rels/.rels", "<?xml version=\"1.0\" encoding=\"UTF-8\"?><Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"xl/workbook.xml\"/></Relationships>",
    ),
    create_part(
      "xl/workbook.xml",
      "<?xml version=\"1.0\" encoding=\"UTF-8\"?><workbook xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\"><sheets><sheet name=\"\{@xml.escape_attribute(sheet_name)}\" sheetId=\"1\" r:id=\"rId1\"/></sheets></workbook>",
    ),
    create_part(
      "xl/_rels/workbook.xml.rels", "<?xml version=\"1.0\" encoding=\"UTF-8\"?><Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet1.xml\"/><Relationship Id=\"rId2\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles\" Target=\"styles.xml\"/></Relationships>",
    ),
    create_part(
      "xl/styles.xml", "<?xml version=\"1.0\" encoding=\"UTF-8\"?><styleSheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\"><fonts count=\"2\"><font><sz val=\"11\"/><name val=\"Arial\"/></font><font><b/><sz val=\"11\"/><name val=\"Arial\"/></font></fonts><fills count=\"1\"><fill><patternFill patternType=\"none\"/></fill></fills><borders count=\"1\"><border/></borders><cellStyleXfs count=\"1\"><xf numFmtId=\"0\" fontId=\"0\" fillId=\"0\" borderId=\"0\"/></cellStyleXfs><cellXfs count=\"2\"><xf numFmtId=\"0\" fontId=\"0\" fillId=\"0\" borderId=\"0\" xfId=\"0\"/><xf numFmtId=\"0\" fontId=\"1\" fillId=\"0\" borderId=\"0\" xfId=\"0\"/></cellXfs><cellStyles count=\"1\"><cellStyle name=\"Normal\" xfId=\"0\" builtinId=\"0\"/></cellStyles></styleSheet>",
    ),
    create_part("xl/worksheets/sheet1.xml", sheet.to_string()),
  ]
  @opc.save({ parts, }) catch {
    error => raise PackageFailure(part="xlsx", message="\{Repr(error)}")
  }
}
