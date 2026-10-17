///|
priv enum RowEdit {
  Insert
  Delete
}

///|
fn row_edit_is_safe(archive : @opc.Package, worksheet : @xml.Element) -> Bool {
  if !sorting_worksheet_is_safe(archive, worksheet) {
    return false
  }
  for child in worksheet.child_elements() {
    match child.local_name() {
      "customSheetViews"
      | "dataConsolidate"
      | "cellWatches"
      | "ignoredErrors"
      | "controls"
      | "oleObjects"
      | "picture" => return false
      "sheetViews" =>
        for view in child.children_named("sheetView") {
          if view.first_child("pane") is Some(_) {
            return false
          }
        }
      _ => ()
    }
  }
  true
}

///|
fn row_edit_blank_row(row : Int32) -> @xml.Node {
  Element(
    element("row", [attribute("r", row.to_string())], [
      Element(element("c", [attribute("r", cell_reference(row, 1))], [])),
    ]),
  )
}

///|
fn row_edit_extent(rows : Array[@xml.Node]) -> String raise XlsxError {
  let mut first_row = max_row
  let mut first_column = max_column
  let mut last_row = 0
  let mut last_column = 0
  for node in rows {
    match node {
      Element(row_element) if row_element.local_name() == "row" => {
        guard row_number(row_element) is Some(row) else {
          raise InvalidWorkbook("edited row has no valid number")
        }
        let mut previous_column = 0
        for cell in row_element.children_named("c") {
          let column = cell_column_or_implicit(cell, row, previous_column)
          if column <= previous_column || column > max_column {
            raise InvalidWorkbook("row has unordered or duplicate cell columns")
          }
          previous_column = column
          if row < first_row {
            first_row = row
          }
          if row > last_row {
            last_row = row
          }
          if column < first_column {
            first_column = column
          }
          if column > last_column {
            last_column = column
          }
        }
      }
      _ => ()
    }
  }
  if last_row == 0 {
    "A1"
  } else {
    let start = cell_reference(first_row, first_column)
    let finish = cell_reference(last_row, last_column)
    if start == finish {
      start
    } else {
      "\{start}:\{finish}"
    }
  }
}

///|
fn row_edit_sheet_data(
  data : @xml.Element,
  at : Int32,
  count : Int32,
  edit : RowEdit,
) -> (@xml.Element, Int32) raise XlsxError {
  let rows : Array[@xml.Node] = []
  let mut previous_row = 0
  let mut inserted = false
  let mut last_row = 0
  for node in data.children {
    match node {
      Element(row_element) if row_element.local_name() == "row" => {
        for child in row_element.child_elements() {
          if child.local_name() != "c" {
            raise InvalidWorkbook(
              "row edit cannot preserve unknown row children",
            )
          }
          if child.first_child("f") is Some(_) ||
            child.first_child("extLst") is Some(_) {
            raise InvalidWorkbook("row edit cannot preserve cell references")
          }
        }
        let source_row = row_number(row_element).unwrap_or(previous_row + 1)
        if source_row <= previous_row || source_row > max_row {
          raise InvalidWorkbook(
            "row edit requires ordered unique worksheet rows",
          )
        }
        previous_row = source_row
        last_row = source_row
        match edit {
          Insert => {
            if !inserted && source_row >= at {
              for row in at..<(at + count) {
                rows.push(row_edit_blank_row(row))
              }
              inserted = true
            }
            let destination = if source_row >= at {
              source_row + count
            } else {
              source_row
            }
            if destination > max_row {
              raise InvalidWorkbook("insert exceeds the XLSX row limit")
            }
            rows.push(
              Element(sorting_rebase_row(row_element, source_row, destination)),
            )
          }
          Delete =>
            if source_row < at {
              rows.push(
                Element(sorting_rebase_row(row_element, source_row, source_row)),
              )
            } else if source_row >= at + count {
              rows.push(
                Element(
                  sorting_rebase_row(
                    row_element,
                    source_row,
                    source_row - count,
                  ),
                ),
              )
            }
        }
      }
      Element(_) =>
        raise InvalidWorkbook("row edit cannot preserve sheetData children")
      _ => rows.push(node)
    }
  }
  match edit {
    Insert if !inserted =>
      for row in at..<(at + count) {
        rows.push(row_edit_blank_row(row))
      }
    _ => ()
  }
  let changed = match edit {
    Insert => count
    Delete =>
      if last_row < at {
        0
      } else if last_row - at + 1 < count {
        last_row - at + 1
      } else {
        count
      }
  }
  ({ name: data.name, attributes: data.attributes, children: rows, }, changed)
}

///|
fn edit_sheet_rows(
  archive : @opc.Package,
  sheet_name : String,
  at : Int32,
  count : Int32,
  edit : RowEdit,
) -> (@opc.Package, Int32) raise XlsxError {
  if at < 1 ||
    at > max_row ||
    count < 1 ||
    count > 100 ||
    count > max_row - at + 1 {
    raise InvalidWorkbook("row edit exceeds bounds")
  }
  if !archive.has_part("xl/workbook.xml") {
    raise MissingWorkbook
  }
  let workbook_xml = parse_part(archive, "xl/workbook.xml")
  if workbook_xml.first_child("definedNames") is Some(_) ||
    archive.has_part("xl/calcChain.xml") {
    raise InvalidWorkbook("row edit cannot preserve workbook references")
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
    !row_edit_is_safe(archive, worksheet) {
    raise InvalidWorkbook(
      "row edit cannot preserve anchored worksheet features",
    )
  }
  for sheet in read(archive).sheets {
    for cell in sheet.cells {
      if cell.value is Formula(..) {
        raise InvalidWorkbook(
          "row edit cannot safely rewrite formula references",
        )
      }
    }
  }
  guard worksheet.first_child("sheetData") is Some(data) else {
    match edit {
      Delete => return (archive, 0)
      Insert => {
        let created = element("sheetData", [], [])
        let children : Array[@xml.Node] = []
        let mut inserted = false
        for node in worksheet.children {
          match node {
            Element(item) if !inserted &&
              comes_after_sheet_data(item.local_name()) => {
              children.push(Element(created))
              inserted = true
            }
            _ => ()
          }
          children.push(node)
        }
        if !inserted {
          children.push(Element(created))
        }
        return edit_sheet_rows(
          archive.replace_text(
            part_name,
            @xml.serialize({
              name: worksheet.name,
              attributes: worksheet.attributes,
              children,
            }),
          ),
          sheet_name,
          at,
          count,
          edit,
        )
      }
    }
  }
  let (updated_data, changed) = row_edit_sheet_data(data, at, count, edit)
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
/// Insert one to 100 empty XLSX rows before `at`. Existing row coordinates,
/// cell values, styles, and unrelated OPC parts are preserved. Workbooks with
/// formulas or row-anchored features are rejected until their references can
/// be rewritten safely.
pub fn insert_sheet_rows(
  archive : @opc.Package,
  sheet_name : String,
  at : Int32,
  count : Int32,
) -> (@opc.Package, Int32) raise XlsxError {
  edit_sheet_rows(archive, sheet_name, at, count, Insert)
}

///|
/// Delete one to 100 XLSX rows from `at`, shifting subsequent rows up. This
/// preserves styles and unrelated OPC parts and rejects formula references or
/// row-anchored features that cannot be rewritten safely.
pub fn delete_sheet_rows(
  archive : @opc.Package,
  sheet_name : String,
  at : Int32,
  count : Int32,
) -> (@opc.Package, Int32) raise XlsxError {
  edit_sheet_rows(archive, sheet_name, at, count, Delete)
}
