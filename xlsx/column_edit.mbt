///|
priv enum ColumnEdit {
  Insert
  Delete
}

///|
fn column_edit_is_safe(
  archive : @opc.Package,
  worksheet : @xml.Element,
) -> Bool {
  if !row_edit_is_safe(archive, worksheet) {
    return false
  }
  for child in worksheet.child_elements() {
    match child.local_name() {
      "cols"
      | "colBreaks"
      | "sheetProtection"
      | "protectedRanges"
      | "scenarios" => return false
      "sheetViews" =>
        for view in child.children_named("sheetView") {
          if view.first_child("selection") is Some(_) {
            return false
          }
        }
      _ => ()
    }
  }
  true
}

///|
fn column_edit_cell(
  cell : @xml.Element,
  row : Int32,
  column : Int32,
) -> @xml.Element {
  {
    name: cell.name,
    attributes: wrap_attribute(
      cell.attributes,
      "r",
      cell_reference(row, column),
    ),
    children: cell.children,
  }
}

///|
fn column_edit_row(
  row_element : @xml.Element,
  row : Int32,
  at : Int32,
  count : Int32,
  edit : ColumnEdit,
) -> (@xml.Element, Int32) raise XlsxError {
  let children : Array[@xml.Node] = []
  let mut previous_column = 0
  let mut inserted = false
  for node in row_element.children {
    guard node is Element(cell) && cell.local_name() == "c" else {
      raise InvalidWorkbook("column edit cannot preserve unknown row children")
    }
    let column = cell_column_or_implicit(cell, row, previous_column)
    if column <= previous_column || column > max_column {
      raise InvalidWorkbook("column edit requires ordered unique cells")
    }
    previous_column = column
    if cell.first_child("f") is Some(_) || cell.first_child("extLst") is Some(_) {
      raise InvalidWorkbook("column edit cannot preserve cell references")
    }
    match edit {
      Insert => {
        if !inserted && column >= at {
          children.push(
            Element(
              element(
                "c",
                [attribute("r", cell_reference(row, at + count - 1))],
                [],
              ),
            ),
          )
          inserted = true
        }
        let destination = if column >= at { column + count } else { column }
        if destination > max_column {
          raise InvalidWorkbook("insert exceeds the XLSX column limit")
        }
        children.push(Element(column_edit_cell(cell, row, destination)))
      }
      Delete =>
        if column < at {
          children.push(Element(column_edit_cell(cell, row, column)))
        } else if column >= at + count {
          children.push(Element(column_edit_cell(cell, row, column - count)))
        }
    }
  }
  if edit is Insert && !inserted {
    children.push(
      Element(
        element("c", [attribute("r", cell_reference(row, at + count - 1))], []),
      ),
    )
  }
  let attributes = row_element.attributes.filter(item => item.name != "spans")
  ({ name: row_element.name, attributes, children, }, previous_column)
}

///|
fn column_edit_sheet_data(
  data : @xml.Element,
  at : Int32,
  count : Int32,
  edit : ColumnEdit,
) -> (@xml.Element, Int32) raise XlsxError {
  let rows : Array[@xml.Node] = []
  let mut previous_row = 0
  let mut last_column = 0
  for node in data.children {
    guard node is Element(row_element) && row_element.local_name() == "row" else {
      raise InvalidWorkbook("column edit cannot preserve sheetData children")
    }
    let row = row_number(row_element).unwrap_or(previous_row + 1)
    if row <= previous_row || row > max_row {
      raise InvalidWorkbook("column edit requires ordered unique rows")
    }
    previous_row = row
    let (updated, row_last_column) = column_edit_row(
      row_element, row, at, count, edit,
    )
    if row_last_column > last_column {
      last_column = row_last_column
    }
    rows.push(Element(updated))
  }
  let changed = match edit {
    Insert => count
    Delete =>
      if last_column < at {
        0
      } else {
        (last_column - at + 1).min(count)
      }
  }
  ({ name: data.name, attributes: data.attributes, children: rows, }, changed)
}

///|
fn edit_sheet_columns(
  archive : @opc.Package,
  sheet_name : String,
  at : Int32,
  count : Int32,
  edit : ColumnEdit,
) -> (@opc.Package, Int32) raise XlsxError {
  if at < 1 ||
    at > max_column ||
    count < 1 ||
    count > 100 ||
    count > max_column - at + 1 {
    raise InvalidWorkbook("column edit exceeds bounds")
  }
  if !archive.has_part("xl/workbook.xml") {
    raise MissingWorkbook
  }
  let workbook_xml = parse_part(archive, "xl/workbook.xml")
  if workbook_xml.first_child("definedNames") is Some(_) ||
    archive.has_part("xl/calcChain.xml") {
    raise InvalidWorkbook("column edit cannot preserve workbook references")
  }
  let descriptors = workbook_sheets(workbook_xml)
  guard descriptor_named(descriptors, sheet_name) is Some(descriptor) else {
    raise SheetNotFound(sheet_name)
  }
  let part_name = worksheet_part_name(
    workbook_relationships(archive),
    descriptor,
  )
  if !archive.has_part(part_name) {
    raise MissingWorksheet(
      sheet=descriptor.name,
      relationship_id=descriptor.relationship_id,
    )
  }
  let worksheet = parse_part(archive, part_name)
  if worksheet.local_name() != "worksheet" ||
    !column_edit_is_safe(archive, worksheet) {
    raise InvalidWorkbook(
      "column edit cannot preserve anchored worksheet features",
    )
  }
  for sheet in read(archive).sheets {
    for cell in sheet.cells {
      if cell.value is Formula(..) {
        raise InvalidWorkbook(
          "column edit cannot safely rewrite formula references",
        )
      }
    }
  }
  guard worksheet.first_child("sheetData") is Some(data) else {
    return (archive, 0)
  }
  let (updated_data, changed) = column_edit_sheet_data(data, at, count, edit)
  if changed == 0 {
    return (archive, 0)
  }
  let extent = row_edit_extent(updated_data.children)
  let children : Array[@xml.Node] = worksheet.children.map(node => {
    match node {
      Element(item) if item.local_name() == "sheetData" => Element(updated_data)
      Element(item) if item.local_name() == "dimension" =>
        Element({
          name: item.name,
          attributes: wrap_attribute(item.attributes, "ref", extent),
          children: item.children,
        })
      _ => node
    }
  })
  (
    archive.replace_text(
      part_name,
      @xml.serialize({
        name: worksheet.name,
        attributes: worksheet.attributes,
        children,
      }),
    ),
    changed,
  )
}

///|
/// Insert one to 100 empty XLSX columns before `at`, shifting existing cells
/// right. Formula-bearing workbooks and anchored worksheet features are
/// rejected because their references cannot yet be rewritten safely.
pub fn insert_sheet_columns(
  archive : @opc.Package,
  sheet_name : String,
  at : Int32,
  count : Int32,
) -> (@opc.Package, Int32) raise XlsxError {
  edit_sheet_columns(archive, sheet_name, at, count, Insert)
}

///|
/// Delete one to 100 XLSX columns from `at`, shifting later cells left.
pub fn delete_sheet_columns(
  archive : @opc.Package,
  sheet_name : String,
  at : Int32,
  count : Int32,
) -> (@opc.Package, Int32) raise XlsxError {
  edit_sheet_columns(archive, sheet_name, at, count, Delete)
}
