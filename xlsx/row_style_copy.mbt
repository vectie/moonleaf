///|
fn row_style_attributes(
  destination : Array[@xml.Attribute],
  source : @xml.Element,
) -> Array[@xml.Attribute] {
  let result = destination.filter(item => {
    item.name != "s" && item.name != "customFormat"
  })
  for item in source.attributes {
    if item.name == "s" || item.name == "customFormat" {
      result.push(item)
    }
  }
  result
}

///|
fn copied_cell_style(cell : @xml.Element, style : String?) -> @xml.Element {
  let attributes = cell.attributes.filter(item => item.name != "s")
  match style {
    Some(value) => attributes.push(attribute("s", value))
    None => ()
  }
  { name: cell.name, attributes, children: cell.children, }
}

///|
fn row_style_cells(
  row : @xml.Element,
  number : Int,
  style_count : Int,
) -> Array[(Int, String?)] raise XlsxError {
  let result : Array[(Int, String?)] = []
  let mut previous = 0
  for child in row.child_elements() {
    if child.local_name() != "c" {
      raise InvalidWorkbook(
        "row style copy cannot preserve unknown row children",
      )
    }
    let column = cell_column_or_implicit(child, number, previous)
    if column <= previous || column > max_column {
      raise InvalidWorkbook("row style copy requires ordered unique cells")
    }
    previous = column
    let style = child.attribute("s")
    match style {
      Some(value) => {
        guard parse_decimal(value, style_count) is Some(index) &&
          index < style_count else {
          raise InvalidWorkbook("cell has an invalid style index")
        }
      }
      None => ()
    }
    result.push((column, style))
  }
  result
}

///|
fn copied_row_styles(
  source : @xml.Element,
  destination : @xml.Element,
  source_number : Int,
  destination_number : Int,
  style_count : Int,
) -> (@xml.Element, Int) raise XlsxError {
  let source_cells = row_style_cells(source, source_number, style_count)
  let destination_cells = row_style_cells(
    destination, destination_number, style_count,
  )
  let attributes = row_style_attributes(destination.attributes, source)
  let mut changed = if attributes == destination.attributes { 0 } else { 1 }
  let source_styles : Map[Int, String] = Map([])
  for (column, style) in source_cells {
    match style {
      Some(value) => source_styles[column] = value
      None => ()
    }
  }
  let children : Array[@xml.Node] = []
  let mut next_source = 0
  let mut next_destination = 0
  for node in destination.children {
    match node {
      Element(cell) if cell.local_name() == "c" => {
        let column = destination_cells[next_destination].0
        next_destination += 1
        while next_source < source_cells.length() &&
              source_cells[next_source].0 < column {
          let (source_column, style) = source_cells[next_source]
          match style {
            Some(value) => {
              children.push(
                Element(
                  element(
                    "c",
                    [
                      attribute(
                        "r",
                        cell_reference(destination_number, source_column),
                      ),
                      attribute("s", value),
                    ],
                    [],
                  ),
                ),
              )
              changed += 1
            }
            None => ()
          }
          next_source += 1
        }
        let style = source_styles.get(column)
        if cell.attribute("s") != style {
          children.push(Element(copied_cell_style(cell, style)))
          changed += 1
        } else {
          children.push(node)
        }
        if next_source < source_cells.length() &&
          source_cells[next_source].0 == column {
          next_source += 1
        }
      }
      _ => children.push(node)
    }
  }
  while next_source < source_cells.length() {
    let (column, style) = source_cells[next_source]
    match style {
      Some(value) => {
        children.push(
          Element(
            element(
              "c",
              [
                attribute("r", cell_reference(destination_number, column)),
                attribute("s", value),
              ],
              [],
            ),
          ),
        )
        changed += 1
      }
      None => ()
    }
    next_source += 1
  }
  ({ name: destination.name, attributes, children, }, changed)
}

///|
/// Copy one existing row's cell formatting to another existing row in the same
/// XLSX sheet. Cell values, formulas, other rows and styles.xml are unchanged.
/// Explicit styles on destination cells without a matching source style are
/// cleared; styled source cells create blank destination cells where needed.
/// Returns the copied package and the number of changed cell/row style records.
pub fn copy_sheet_row_styles(
  archive : @opc.Package,
  sheet_name : String,
  source_row : Int,
  destination_row : Int,
) -> (@opc.Package, Int) raise XlsxError {
  if source_row < 1 ||
    source_row > max_row ||
    destination_row < 1 ||
    destination_row > max_row ||
    source_row == destination_row {
    raise InvalidWorkbook("row style copy requires distinct valid rows")
  }
  if !archive.has_part("xl/workbook.xml") {
    raise MissingWorkbook
  }
  let relationships = workbook_relationships(archive)
  let workbook = parse_part(archive, "xl/workbook.xml")
  guard descriptor_named(workbook_sheets(workbook), sheet_name)
    is Some(descriptor) else {
    raise SheetNotFound(sheet_name)
  }
  let part_name = worksheet_part_name(relationships, descriptor)
  if !archive.has_part(part_name) {
    raise MissingWorksheet(
      sheet=sheet_name,
      relationship_id=descriptor.relationship_id,
    )
  }
  let worksheet = parse_part(archive, part_name)
  guard worksheet.local_name() == "worksheet" &&
    worksheet.first_child("sheetData") is Some(data) else {
    raise InvalidWorkbook("row style copy needs worksheet data")
  }
  let styles = parse_part(archive, wrap_styles_part(archive, relationships))
  guard styles.first_child("cellXfs") is Some(xfs) else {
    raise InvalidWorkbook("workbook has no cell styles")
  }
  let style_count = xfs.children_named("xf").length()
  let mut source : @xml.Element? = None
  let mut destination : @xml.Element? = None
  let mut previous = 0
  for row in data.children_named("row") {
    guard row_number(row) is Some(number) && number > previous else {
      raise InvalidWorkbook("row style copy requires ordered numbered rows")
    }
    previous = number
    if number == source_row {
      source = Some(row)
    }
    if number == destination_row {
      destination = Some(row)
    }
  }
  guard source is Some(source) && destination is Some(destination) else {
    raise InvalidWorkbook(
      "row style copy requires existing source and destination rows",
    )
  }
  for row in [source, destination] {
    match row.attribute("s") {
      Some(value) => {
        guard parse_decimal(value, style_count) is Some(index) &&
          index < style_count else {
          raise InvalidWorkbook("row has an invalid style index")
        }
      }
      None => ()
    }
  }
  let (copied, changed) = copied_row_styles(
    source, destination, source_row, destination_row, style_count,
  )
  if changed == 0 {
    return (archive, 0)
  }
  let rows : Array[@xml.Node] = data.children.map(node => {
    match node {
      Element(row) if row_number(row) == Some(destination_row) =>
        Element(copied)
      _ => node
    }
  })
  let updated_data : @xml.Element = {
    name: data.name,
    attributes: data.attributes,
    children: rows,
  }
  let extent = row_edit_extent(rows)
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
