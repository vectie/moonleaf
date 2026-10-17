///|
/// Remove the content of existing cells while retaining their coordinates,
/// styles, and all unrelated worksheet/package parts. A formula is content and
/// is removed with its cached value. Missing or already empty cells are no-ops.
pub fn clear_sheet_range(
  xlsx_package : @opc.Package,
  sheet_name : String,
  start_row : Int32,
  start_column : Int32,
  end_row : Int32,
  end_column : Int32,
) -> (@opc.Package, Int32) raise XlsxError {
  if start_row < 1 ||
    start_column < 1 ||
    end_row < start_row ||
    end_column < start_column ||
    end_row > max_row ||
    end_column > max_column ||
    (end_row - start_row + 1) * (end_column - start_column + 1) > 1_000 {
    raise InvalidWorkbook("clear range exceeds bounds")
  }
  if !xlsx_package.has_part("xl/workbook.xml") {
    raise MissingWorkbook
  }
  let descriptors = workbook_sheets(parse_part(xlsx_package, "xl/workbook.xml"))
  guard descriptor_named(descriptors, sheet_name) is Some(descriptor) else {
    raise SheetNotFound(sheet_name)
  }
  let part_name = worksheet_part_name(
    workbook_relationships(xlsx_package),
    descriptor,
  )
  if !xlsx_package.has_part(part_name) {
    raise MissingWorksheet(
      sheet=descriptor.name,
      relationship_id=descriptor.relationship_id,
    )
  }
  let worksheet = parse_part(xlsx_package, part_name)
  guard worksheet.local_name() == "worksheet" else {
    raise InvalidWorkbook("worksheet part has an invalid root")
  }
  let changed = Ref(0)
  let children : Array[@xml.Node] = worksheet.children.map(child => {
    match child {
      Element(data) if data.local_name() == "sheetData" => {
        let mut previous_row = 0
        let rows : Array[@xml.Node] = data.children.map(row_child => {
          match row_child {
            Element(row_element) if row_element.local_name() == "row" => {
              let row = row_number(row_element).unwrap_or(previous_row + 1)
              previous_row = row
              if row < start_row || row > end_row {
                row_child
              } else {
                let mut previous_column = 0
                let cells : Array[@xml.Node] = row_element.children.map(cell_child => {
                  match cell_child {
                    Element(cell) if cell.local_name() == "c" => {
                      let column = cell_column_or_implicit(
                        cell, row, previous_column,
                      )
                      previous_column = column
                      if column < start_column || column > end_column {
                        cell_child
                      } else {
                        let values = cell.children.filter(fn(node) {
                          match node {
                            Element(value) =>
                              value.local_name() == "v" ||
                              value.local_name() == "is" ||
                              value.local_name() == "f"
                            _ => false
                          }
                        })
                        if values.is_empty() {
                          cell_child
                        } else {
                          changed.val += 1
                          Element({
                            name: cell.name,
                            attributes: cell.attributes.filter(fn(attribute) {
                              attribute.name != "t"
                            }),
                            children: cell.children.filter(fn(node) {
                              match node {
                                Element(value) =>
                                  value.local_name() != "v" &&
                                  value.local_name() != "is" &&
                                  value.local_name() != "f"
                                _ => true
                              }
                            }),
                          })
                        }
                      }
                    }
                    _ => cell_child
                  }
                })
                Element({
                  name: row_element.name,
                  attributes: row_element.attributes,
                  children: cells,
                })
              }
            }
            _ => row_child
          }
        })
        Element({
          name: data.name,
          attributes: data.attributes,
          children: rows,
        })
      }
      _ => child
    }
  })
  if changed.val == 0 {
    return (xlsx_package, 0)
  }
  (
    xlsx_package.replace_text(
      part_name,
      @xml.serialize({
        name: worksheet.name,
        attributes: worksheet.attributes,
        children,
      }),
    ),
    changed.val,
  )
}
