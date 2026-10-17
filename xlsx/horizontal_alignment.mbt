///|
/// Horizontal alignment choices supported by the spreadsheet Home ribbon.
pub(all) enum HorizontalAlignment {
  Left
  Center
  Right
}

///|
fn horizontal_name(alignment : HorizontalAlignment) -> String {
  match alignment {
    Left => "left"
    Center => "center"
    Right => "right"
  }
}

///|
/// Set horizontal alignment on an XLSX range, including blank cells. Other
/// alignment properties such as wrapText, fonts, formulas and values remain.
pub fn set_horizontal_alignment_range(
  xlsx_package : @opc.Package,
  sheet_name : String,
  start_row : Int32,
  start_column : Int32,
  end_row : Int32,
  end_column : Int32,
  alignment : HorizontalAlignment,
) -> (@opc.Package, Int32) raise XlsxError {
  set_cell_style_range(
    xlsx_package,
    sheet_name,
    start_row,
    start_column,
    end_row,
    end_column,
    Horizontal(horizontal_name(alignment)),
  )
}

///|
/// Report explicit horizontal alignment on existing cells in one-based
/// coordinates. Unstyled cells are omitted and retain spreadsheet defaults.
pub fn horizontal_alignment_cells(
  xlsx_package : @opc.Package,
  sheet_name : String,
) -> Array[(Int32, Int32, String)] raise XlsxError {
  if !xlsx_package.has_part("xl/workbook.xml") {
    raise MissingWorkbook
  }
  let descriptors = workbook_sheets(parse_part(xlsx_package, "xl/workbook.xml"))
  guard descriptor_named(descriptors, sheet_name) is Some(descriptor) else {
    raise SheetNotFound(sheet_name)
  }
  let relationships = workbook_relationships(xlsx_package)
  let sheet_part = worksheet_part_name(relationships, descriptor)
  if !relationships.any(relationship => {
      !relationship.external &&
      styles_relationship_types.contains(relationship.relationship_type)
    }) {
    return []
  }
  let style_part = wrap_styles_part(xlsx_package, relationships)
  guard parse_part(xlsx_package, style_part).first_child("cellXfs")
    is Some(cell_xfs) else {
    raise InvalidWorkbook("workbook has no cell styles")
  }
  let styles = cell_xfs.children_named("xf")
  let worksheet = parse_part(xlsx_package, sheet_part)
  let result : Array[(Int32, Int32, String)] = []
  match worksheet.first_child("sheetData") {
    Some(data) => {
      let mut previous_row = 0
      for row_element in data.children_named("row") {
        let row = row_number(row_element).unwrap_or(previous_row + 1)
        previous_row = row
        let inherited_style = integer_attribute(row_element, "s", 65535).unwrap_or(
          0,
        )
        let mut previous_column = 0
        for cell in row_element.children_named("c") {
          let column = cell_column_or_implicit(cell, row, previous_column)
          previous_column = column
          let style_id = integer_attribute(cell, "s", 65535).unwrap_or(
            inherited_style,
          )
          if style_id >= styles.length() {
            raise InvalidWorkbook("cell has an invalid style index")
          }
          match styles[style_id].first_child("alignment") {
            Some(alignment) =>
              match alignment.attribute("horizontal") {
                Some(value) if !value.is_empty() =>
                  result.push((row, column, value))
                _ => ()
              }
            None => ()
          }
        }
      }
    }
    None => ()
  }
  result
}
