///|
fn sorting_row_attribute(
  attributes : Array[@xml.Attribute],
  destination_row : Int,
) -> Array[@xml.Attribute] {
  let updated : Array[@xml.Attribute] = []
  let mut found = false
  for item in attributes {
    if item.name == "r" {
      updated.push({ name: "r", value: "\{destination_row}", })
      found = true
    } else {
      updated.push(item)
    }
  }
  if !found {
    updated.push({ name: "r", value: "\{destination_row}", })
  }
  updated
}

///|
fn sorting_rebase_row(
  source : @xml.Element,
  source_row : Int,
  destination_row : Int,
) -> @xml.Element raise XlsxError {
  let children : Array[@xml.Node] = []
  let mut previous_column = 0
  for node in source.children {
    match node {
      Element(cell) if cell.local_name() == "c" => {
        let column = cell_column_or_implicit(cell, source_row, previous_column)
        if column < 1 || column > max_column || column <= previous_column {
          raise InvalidWorkbook("sort requires ordered unique cell columns")
        }
        previous_column = column
        let attributes : Array[@xml.Attribute] = []
        for item in cell.attributes {
          if item.name == "r" {
            attributes.push({
              name: "r",
              value: cell_reference(destination_row, column),
            })
          } else {
            attributes.push(item)
          }
        }
        children.push(
          Element({ name: cell.name, attributes, children: cell.children, }),
        )
      }
      _ => children.push(node)
    }
  }
  {
    name: source.name,
    attributes: sorting_row_attribute(source.attributes, destination_row),
    children,
  }
}

///|
fn sorting_worksheet_is_safe(
  archive : @opc.Package,
  worksheet : @xml.Element,
) -> Bool {
  for part in archive.parts {
    if part.name.has_prefix("xl/worksheets/_rels/") {
      return false
    }
  }
  for child in worksheet.child_elements() {
    match child.local_name() {
      "mergeCells"
      | "conditionalFormatting"
      | "dataValidations"
      | "hyperlinks"
      | "drawing"
      | "legacyDrawing"
      | "tableParts"
      | "pivotTable"
      | "extLst"
      | "rowBreaks"
      | "autoFilter"
      | "sortState" => return false
      _ => ()
    }
  }
  true
}

///| Sort complete worksheet rows into a new OPC package, keeping each row's

///| cells and formatting together. The first row remains fixed when

///| `has_header` is true. Formula-bearing workbooks and row-anchored features

///| are rejected because safely rewriting their references needs a richer

///|
/// dependency model.
pub fn sort_sheet_rows(
  archive : @opc.Package,
  sheet_name : String,
  column : Int,
  descending : Bool,
  has_header : Bool,
) -> (@opc.Package, Int) raise XlsxError {
  if column < 1 || column > max_column {
    raise InvalidCoordinates(row=1, column~)
  }
  if !archive.has_part("xl/workbook.xml") {
    raise MissingWorkbook
  }
  let workbook_xml = parse_part(archive, "xl/workbook.xml")
  if workbook_xml.first_child("definedNames") is Some(_) ||
    archive.has_part("xl/calcChain.xml") {
    raise InvalidWorkbook("sort cannot preserve workbook row references")
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
      sheet=sheet_name,
      relationship_id=descriptor.relationship_id,
    )
  }
  let worksheet = parse_part(archive, part_name)
  if worksheet.local_name() != "worksheet" ||
    !sorting_worksheet_is_safe(archive, worksheet) {
    raise InvalidWorkbook(
      "sort cannot preserve row-anchored worksheet features",
    )
  }
  let workbook = read(archive)
  for sheet in workbook.sheets {
    for cell in sheet.cells {
      if cell.value is Formula(..) {
        raise InvalidWorkbook("sort cannot safely update formula references")
      }
    }
  }
  guard worksheet.first_child("sheetData") is Some(sheet_data) else {
    return (archive, 0)
  }
  let source_rows : Array[@xml.Element] = []
  for row in sheet_data.children_named("row") {
    let expected = source_rows.length() + 1
    if expected > 10_000 || row_number(row).unwrap_or(expected) != expected {
      raise InvalidWorkbook("sort requires contiguous worksheet rows")
    }
    source_rows.push(row)
  }
  let start = if has_header { 1 } else { 0 }
  if source_rows.length() <= start + 1 {
    return (archive, 0)
  }
  let keys : Array[String] = []
  for _ in start..<source_rows.length() {
    keys.push("")
  }
  for sheet in workbook.sheets {
    if sheet.name == sheet_name {
      for cell in sheet.cells {
        if cell.column == column &&
          cell.row > start &&
          cell.row <= source_rows.length() {
          keys[cell.row - start - 1] = match cell.value {
            Empty => ""
            Text(text) | Number(text) | Error(text) => text
            Boolean(flag) => if flag { "TRUE" } else { "FALSE" }
            Formula(..) => ""
          }
        }
      }
    }
  }
  let order = @scene.sort_row_indices(keys, descending)
  let rows : Array[@xml.Node] = []
  if start == 1 {
    rows.push(Element(source_rows[0]))
  }
  for position, source_index in order {
    let original = source_rows[start + source_index]
    rows.push(
      Element(
        sorting_rebase_row(
          original,
          start + source_index + 1,
          start + position + 1,
        ),
      ),
    )
  }
  let children : Array[@xml.Node] = []
  for child in worksheet.children {
    match child {
      Element(element) if element.local_name() == "sheetData" =>
        children.push(
          Element({
            name: element.name,
            attributes: element.attributes,
            children: rows,
          }),
        )
      _ => children.push(child)
    }
  }
  let updated : @xml.Element = {
    name: worksheet.name,
    attributes: worksheet.attributes,
    children,
  }
  (archive.replace_text(part_name, @xml.serialize(updated)), order.length())
}
