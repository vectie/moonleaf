///|
fn create_part(name : String, content : String) -> @opc.Part {
  { name, content: @utf8.encode(content).to_fixedarray(), }
}

///|
fn write_created_cell(
  output : StringBuilder,
  value : @scene.CellValue,
  reference : String,
  header : Bool,
) -> Unit raise XlsxError {
  let style = if header { "1" } else { "0" }
  output <+ "<c r=\"\{reference}\" s=\"\{style}\""
  match value {
    Empty => output <+ "/>"
    Number(number) => {
      output <+ "><v>"
      write_created_xml_text(output, number)
      output <+ "</v></c>"
    }
    Boolean(flag) =>
      output <+ " t=\"b\"><v>\{if flag { "1" } else { "0" }}</v></c>"
    Text(text) | Error(text) => {
      output <+ " t=\"inlineStr\"><is><t xml:space=\"preserve\">"
      write_created_xml_text(output, text)
      output <+ "</t></is></c>"
    }
    Formula(expression~, cached~) => {
      output <+ "><f>"
      write_created_xml_text(output, expression)
      output <+ "</f>"
      if cached is Some(value) {
        output <+ "<v>"
        write_created_xml_text(output, value)
        output <+ "</v>"
      }
      output <+ "</c>"
    }
  }
}

///|
fn valid_xml_cell_text(text : String) -> Bool {
  for character in text.iter() {
    let code = character.to_int()
    if (code < 0x20 && code != 0x9 && code != 0xA && code != 0xD) ||
      code == 0xFFFE ||
      code == 0xFFFF {
      return false
    }
  }
  true
}

///|
/// Create a single-sheet XLSX using MoonLeaf's OPC ZIP writer.
/// Strings are stored as literal inline strings, including text beginning with '='.
pub fn create(
  rows : Array[Array[@scene.CellValue]],
  sheet_name? : String = "研究证据",
) -> FixedArray[Byte] raise XlsxError {
  // Count UTF-16 units explicitly, including both units of supplementary
  // characters, while preserving XML-valid whitespace through references.
  let mut sheet_name_units = 0
  for character in sheet_name.iter() {
    sheet_name_units += if character.to_int() > 0xFFFF { 2 } else { 1 }
  }
  if rows.length() > 10_001 ||
    sheet_name_units == 0 ||
    sheet_name_units > 31 ||
    !valid_xml_cell_text(sheet_name) ||
    sheet_name.has_prefix("'") ||
    sheet_name.has_suffix("'") {
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
      let valid = match value {
        Empty | Boolean(_) => true
        Text(text) | Number(text) | Error(text) => {
          if text.length() > 32767 {
            raise InvalidWorkbook(
              "XLSX cell exceeds Excel's 32767 character limit",
            )
          }
          valid_xml_cell_text(text)
        }
        Formula(expression~, cached~) =>
          valid_xml_cell_text(expression) &&
          valid_xml_cell_text(cached.unwrap_or(""))
      }
      if !valid {
        raise InvalidWorkbook("XLSX cell contains an invalid XML character")
      }
      total_text += match value {
        Empty | Boolean(_) => 0
        Text(text) | Number(text) | Error(text) => text.length()
        Formula(expression~, cached~) =>
          expression.length() + cached.unwrap_or("").length()
      }
      if total_text > 8_388_608 {
        raise InvalidWorkbook("XLSX exceeds 8 Mi UTF-16 units of cell text")
      }
      write_created_cell(
        sheet,
        value,
        cell_reference(row_index + 1, column_index + 1),
        row_index == 0,
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
      "<?xml version=\"1.0\" encoding=\"UTF-8\"?><workbook xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\"><sheets><sheet name=\"\{created_xml_attribute(sheet_name)}\" sheetId=\"1\" r:id=\"rId1\"/></sheets></workbook>",
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

///|
/// Create a bounded workbook with distinct named sheets using the existing
/// single-sheet cell writer. Strings remain literal and numeric cells remain
/// numeric. The total cell/text budgets apply across the entire workbook.
pub fn create_workbook(
  sheets : Array[(String, Array[Array[@scene.CellValue]])],
) -> FixedArray[Byte] raise XlsxError {
  guard sheets.length() >= 1 && sheets.length() <= 20 else {
    raise InvalidWorkbook("XLSX workbook needs 1..20 sheets")
  }
  let names : Array[String] = []
  let parts : Array[@opc.Part] = []
  let content_types = StringBuilder()
  let workbook = StringBuilder()
  let relationships = StringBuilder()
  content_types <+
    "<?xml version=\"1.0\" encoding=\"UTF-8\"?><Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Default Extension=\"xml\" ContentType=\"application/xml\"/><Override PartName=\"/xl/workbook.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml\"/><Override PartName=\"/xl/styles.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml\"/>"
  workbook <+
    "<?xml version=\"1.0\" encoding=\"UTF-8\"?><workbook xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\"><sheets>"
  relationships <+
    "<?xml version=\"1.0\" encoding=\"UTF-8\"?><Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">"
  let mut total_cells = 0
  let mut total_text = 0
  for index, (name, rows) in sheets {
    let folded = name.to_lower()
    guard !names.contains(folded) else {
      raise InvalidWorkbook("XLSX sheet names must be distinct ignoring case")
    }
    names.push(folded)
    for row in rows {
      total_cells += row.length()
      for value in row {
        total_text += match value {
          Empty | Boolean(_) => 0
          Text(text) | Number(text) | Error(text) => text.length()
          Formula(expression~, cached~) =>
            expression.length() + cached.unwrap_or("").length()
        }
      }
    }
    guard total_cells <= 100000 && total_text <= 8388608 else {
      raise InvalidWorkbook("XLSX workbook exceeds total cell/text budget")
    }
    let archive = @opc.open(create(rows, sheet_name=name)) catch {
      error => raise PackageFailure(part="xlsx", message="\{Repr(error)}")
    }
    let number = index + 1
    let path = "xl/worksheets/sheet\{number}.xml"
    parts.push(
      create_part(
        path,
        created_package_text(archive, "xl/worksheets/sheet1.xml"),
      ),
    )
    if index == 0 {
      parts.push(
        create_part(
          "xl/styles.xml",
          created_package_text(archive, "xl/styles.xml"),
        ),
      )
      parts.push(
        create_part("_rels/.rels", created_package_text(archive, "_rels/.rels")),
      )
    }
    content_types <+
      "<Override PartName=\"/\{path}\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/>"
    workbook <+
      "<sheet name=\"\{created_xml_attribute(name)}\" sheetId=\"\{number}\" r:id=\"rId\{number}\"/>"
    relationships <+
      "<Relationship Id=\"rId\{number}\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet\{number}.xml\"/>"
  }
  content_types <+ "</Types>"
  workbook <+ "</sheets></workbook>"
  relationships <+
    "<Relationship Id=\"rId\{sheets.length() + 1}\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles\" Target=\"styles.xml\"/></Relationships>"
  parts.push(create_part("[Content_Types].xml", content_types.to_string()))
  parts.push(create_part("xl/workbook.xml", workbook.to_string()))
  parts.push(
    create_part("xl/_rels/workbook.xml.rels", relationships.to_string()),
  )
  @opc.save({ parts, }) catch {
    error => raise PackageFailure(part="xlsx", message="\{Repr(error)}")
  }
}

///|
fn created_package_text(
  archive : @opc.Package,
  name : String,
) -> String raise XlsxError {
  archive.text(name) catch {
    error => raise PackageFailure(part=name, message="\{Repr(error)}")
  }
}
