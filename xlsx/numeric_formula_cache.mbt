///|
/// Numeric display coordinates for formula caches. The XML result type is
/// authoritative: a boolean/text cache such as "1" must not receive a numeric
/// display merely because its text can be parsed as a number.
pub fn numeric_formula_cells(
  archive : @opc.Package,
  sheet_name : String,
) -> Array[(Int, Int)] raise XlsxError {
  let workbook = parse_part(archive, "xl/workbook.xml")
  guard descriptor_named(workbook_sheets(workbook), sheet_name)
    is Some(descriptor) else {
    raise SheetNotFound(sheet_name)
  }
  let root = parse_part(
    archive,
    worksheet_part_name(workbook_relationships(archive), descriptor),
  )
  let result : Array[(Int, Int)] = []
  let mut previous_row = 0
  if root.first_child("sheetData") is Some(data) {
    for row in data.children_named("row") {
      let logical_row = integer_attribute(row, "r", max_row).unwrap_or(
        previous_row + 1,
      )
      previous_row = logical_row
      let mut previous_column = 0
      for cell in row.children_named("c") {
        let (r, c) = match cell.attribute("r") {
          Some(reference) =>
            parse_cell_reference(reference).unwrap_or_else(() => {
              raise InvalidCellReference(reference)
            })
          None => (logical_row, previous_column + 1)
        }
        previous_column = c
        if cell.first_child("f") is Some(_) &&
          (cell.attribute("t") is None || cell.attribute("t") == Some("n")) {
          if child_text(cell, "v") is Some(text) {
            let number = @string.parse_double(text.trim()) catch {
              _ => continue
            }
            if !number.is_nan() && !number.is_inf() {
              result.push((r, c))
            }
          }
        }
      }
    }
  }
  result
}
