///|
/// Common number formats exposed by the spreadsheet Home ribbon.
pub(all) enum NumberFormatPreset {
  FormatGeneral
  FormatNumber
  FormatPercent
  FormatCurrency
}

///|
let currency_format_code = "\"¥\"#,##0.00;[Red]-\"¥\"#,##0.00"

///|
fn custom_format_part(
  xlsx_package : @opc.Package,
  format_code : String,
) -> (@opc.Package, Int) raise XlsxError {
  let relationships = workbook_relationships(xlsx_package)
  let styles_part = wrap_styles_part(xlsx_package, relationships)
  let style_sheet = parse_part(xlsx_package, styles_part)
  if style_sheet.local_name() != "styleSheet" {
    raise InvalidWorkbook("workbook has no editable styles part")
  }
  let formats = match style_sheet.first_child("numFmts") {
    Some(part) => part.children_named("numFmt")
    None => []
  }
  let used : Array[Int] = []
  for item in formats {
    guard integer_attribute(item, "numFmtId", 65535) is Some(id) &&
      item.attribute("formatCode") is Some(code) else {
      raise InvalidWorkbook("invalid XLSX custom number format")
    }
    if id < 164 || used.contains(id) {
      raise InvalidWorkbook("invalid XLSX custom number format index")
    }
    if code == format_code {
      return (xlsx_package, id)
    }
    used.push(id)
  }
  let mut id = 164
  while used.contains(id) {
    id += 1
  }
  if id > 65535 {
    raise InvalidWorkbook("too many XLSX custom number formats")
  }
  let created : @xml.Node = Element(
    element(
      "numFmt",
      [
        attribute("numFmtId", id.to_string()),
        attribute("formatCode", format_code),
      ],
      [],
    ),
  )
  let mut found = false
  let children : Array[@xml.Node] = []
  for child in style_sheet.children {
    match child {
      Element(part) if part.local_name() == "numFmts" => {
        let formats = part.children.copy()
        formats.push(created)
        children.push(
          Element({
            name: part.name,
            attributes: wrap_attribute(
              part.attributes,
              "count",
              (part.children_named("numFmt").length() + 1).to_string(),
            ),
            children: formats,
          }),
        )
        found = true
      }
      _ => children.push(child)
    }
  }
  if !found {
    let original = children.copy()
    children.clear()
    children.push(
      Element(element("numFmts", [attribute("count", "1")], [created])),
    )
    children.append(original)
  }
  (
    xlsx_package.replace_text(
      styles_part,
      @xml.serialize({
        name: style_sheet.name,
        attributes: style_sheet.attributes,
        children,
      }),
    ),
    id,
  )
}

///|
/// Format a bounded XLSX selection. Numeric values and formulas are retained;
/// currency uses an explicit yen/yuan symbol and two decimal places.
pub fn set_number_format_range(
  xlsx_package : @opc.Package,
  sheet_name : String,
  start_row : Int,
  start_column : Int,
  end_row : Int,
  end_column : Int,
  preset : NumberFormatPreset,
) -> (@opc.Package, Int) raise XlsxError {
  let (source, id) = match preset {
    FormatGeneral => (xlsx_package, 0)
    FormatNumber => (xlsx_package, 4)
    FormatPercent => (xlsx_package, 10)
    FormatCurrency => custom_format_part(xlsx_package, currency_format_code)
  }
  set_cell_style_range(
    source,
    sheet_name,
    start_row,
    start_column,
    end_row,
    end_column,
    NumberFormat(id),
  )
}

///|
fn decimal_format_code(preset : NumberFormatPreset, places : Int) -> String {
  let digits = StringBuilder()
  if places > 0 {
    digits.write_char('.')
    for _ in 0..<places {
      digits.write_char('0')
    }
  }
  let suffix = digits.to_string()
  match preset {
    FormatNumber => "#,##0" + suffix
    FormatPercent => "0" + suffix + "%"
    FormatCurrency => "\"¥\"#,##0" + suffix + ";[Red]-\"¥\"#,##0" + suffix
    FormatGeneral => "General"
  }
}

///|
/// Set an explicit zero-to-six decimal count for Number, Percent or Currency.
/// The XLSX cell values, formulas and other style properties are preserved.
pub fn set_number_format_places_range(
  xlsx_package : @opc.Package,
  sheet_name : String,
  start_row : Int,
  start_column : Int,
  end_row : Int,
  end_column : Int,
  preset : NumberFormatPreset,
  decimal_places : Int,
) -> (@opc.Package, Int) raise XlsxError {
  if decimal_places < 0 || decimal_places > 6 || preset is FormatGeneral {
    raise InvalidWorkbook(
      "decimal places require Number, Percent or Currency from 0 to 6",
    )
  }
  let code = decimal_format_code(preset, decimal_places)
  let (source, id) = custom_format_part(xlsx_package, code)
  set_cell_style_range(
    source,
    sheet_name,
    start_row,
    start_column,
    end_row,
    end_column,
    NumberFormat(id),
  )
}

///|
fn generated_format_label(code : String) -> String? {
  for places in 0..<=6 {
    if code == decimal_format_code(FormatNumber, places) {
      return Some("number")
    }
    if code == decimal_format_code(FormatPercent, places) {
      return Some("percent")
    }
    if code == decimal_format_code(FormatCurrency, places) {
      return Some("currency")
    }
  }
  None
}

///|
fn generated_format_places(code : String) -> Int? {
  for places in 0..<=6 {
    if code == decimal_format_code(FormatNumber, places) ||
      code == decimal_format_code(FormatPercent, places) ||
      code == decimal_format_code(FormatCurrency, places) {
      return Some(places)
    }
  }
  None
}

///|
fn known_format_places(id : Int, code : String?) -> Int? {
  match code {
    Some(value) => {
      if value == currency_format_code {
        return Some(2)
      }
      return generated_format_places(value)
    }
    None => ()
  }
  match id {
    1 | 3 | 5 | 6 | 9 | 37 | 38 | 42 => Some(0)
    2 | 4 | 7 | 8 | 10 | 39 | 40 | 44 => Some(2)
    _ => None
  }
}

///|
/// Report known decimal counts for styled XLSX cells. Unknown custom formats
/// are omitted so a viewer cannot claim a precision it has not parsed.
pub fn number_format_places_cells(
  xlsx_package : @opc.Package,
  sheet_name : String,
) -> Array[(Int, Int, Int)] raise XlsxError {
  let result : Array[(Int, Int, Int)] = []
  for cell in inspect(xlsx_package) {
    if cell.sheet_name == sheet_name {
      match cell.number_format_id {
        Some(id) =>
          match known_format_places(id, cell.number_format) {
            Some(places) => result.push((cell.row, cell.column, places))
            None => ()
          }
        None => ()
      }
    }
  }
  result
}

///|
fn number_format_label(id : Int, code : String?) -> String? {
  if id == 0 {
    None
  } else if id == 9 || id == 10 {
    Some("percent")
  } else if code is Some(format_code) &&
    generated_format_label(format_code) is Some(label) {
    Some(label)
  } else if (id >= 5 && id <= 8) ||
    id == 42 ||
    id == 44 ||
    code == Some(currency_format_code) {
    Some("currency")
  } else if (id >= 1 && id <= 4) || (id >= 37 && id <= 40) {
    Some("number")
  } else {
    Some("custom")
  }
}

///|
/// Report one-based coordinates and non-General number-format labels from the
/// saved XLSX styles. An omitted cell has General/default formatting.
pub fn number_format_cells(
  xlsx_package : @opc.Package,
  sheet_name : String,
) -> Array[(Int, Int, String)] raise XlsxError {
  let result : Array[(Int, Int, String)] = []
  for cell in inspect(xlsx_package) {
    if cell.sheet_name == sheet_name {
      match cell.number_format_id {
        Some(id) =>
          match number_format_label(id, cell.number_format) {
            Some(label) => result.push((cell.row, cell.column, label))
            None => ()
          }
        None => ()
      }
    }
  }
  result
}
