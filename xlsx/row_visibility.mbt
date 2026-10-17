///|
fn visible_row_attributes(
  attributes : Array[@xml.Attribute],
  hide : Bool,
) -> Array[@xml.Attribute] {
  let result : Array[@xml.Attribute] = []
  for item in attributes {
    if item.name != "hidden" {
      result.push(item)
    }
  }
  if hide {
    result.push(attribute("hidden", "1"))
  }
  result
}

///|
fn visible_row_state(row : @xml.Element) -> Bool raise XlsxError {
  match row.attribute("hidden") {
    None | Some("0") | Some("false") => false
    Some("1") | Some("true") => true
    Some(_) => raise InvalidWorkbook("row has an unknown hidden state")
  }
}

///|
/// Return the one-based row numbers marked hidden in an XLSX worksheet.
/// A preview can omit these rows while retaining their cell coordinates for
/// editing and undo. The result is bounded by the preview's 10,000-row limit.
pub fn hidden_sheet_rows(
  archive : @opc.Package,
  sheet_name : String,
) -> Array[Int32] raise XlsxError {
  if !archive.has_part("xl/workbook.xml") {
    raise MissingWorkbook
  }
  let workbook = parse_part(archive, "xl/workbook.xml")
  guard descriptor_named(workbook_sheets(workbook), sheet_name)
    is Some(descriptor) else {
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
  if worksheet.local_name() != "worksheet" {
    raise InvalidWorkbook("row visibility requires an XLSX worksheet")
  }
  let hidden : Array[Int32] = []
  let mut previous = 0
  match worksheet.first_child("sheetData") {
    Some(data) =>
      for row in data.children_named("row") {
        guard row_number(row) is Some(number) else {
          raise InvalidWorkbook(
            "row visibility requires numbered worksheet rows",
          )
        }
        if number <= previous || number > 10_000 {
          raise InvalidWorkbook("row visibility exceeds ordered preview rows")
        }
        previous = number
        if visible_row_state(row) {
          hidden.push(number)
        }
      }
    None => ()
  }
  hidden
}

///|
fn set_sheet_rows_hidden(
  archive : @opc.Package,
  sheet_name : String,
  at : Int32,
  count : Int32,
  hide : Bool,
) -> (@opc.Package, Int32) raise XlsxError {
  if at < 1 ||
    at > max_row ||
    count < 1 ||
    count > 100 ||
    count > max_row - at + 1 {
    raise InvalidWorkbook("row visibility selection exceeds bounds")
  }
  if !archive.has_part("xl/workbook.xml") {
    raise MissingWorkbook
  }
  let workbook = parse_part(archive, "xl/workbook.xml")
  guard descriptor_named(workbook_sheets(workbook), sheet_name)
    is Some(descriptor) else {
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
    !row_edit_is_safe(archive, worksheet) {
    raise InvalidWorkbook(
      "row visibility cannot preserve anchored worksheet features",
    )
  }
  // Keep the same conservative workbook gate as the row editor. This ensures
  // the saved copy cannot silently alter formula-bearing or anchored sheets.
  for sheet in read(archive).sheets {
    for cell in sheet.cells {
      if cell.value is Formula(..) {
        raise InvalidWorkbook(
          "row visibility cannot verify formula-bearing workbook",
        )
      }
    }
  }
  let data = match worksheet.first_child("sheetData") {
    Some(value) => value
    None => element("sheetData", [], [])
  }
  let rows : Array[@xml.Node] = []
  let mut previous = 0
  let mut next_target = at
  let mut changed = 0
  for node in data.children {
    match node {
      Element(row) if row.local_name() == "row" => {
        guard row_number(row) is Some(number) else {
          raise InvalidWorkbook(
            "row visibility requires numbered worksheet rows",
          )
        }
        if number <= previous {
          raise InvalidWorkbook(
            "row visibility requires ordered unique worksheet rows",
          )
        }
        previous = number
        for child in row.child_elements() {
          if child.local_name() != "c" ||
            child.first_child("f") is Some(_) ||
            child.first_child("extLst") is Some(_) {
            raise InvalidWorkbook(
              "row visibility cannot preserve unknown row children",
            )
          }
        }
        while hide && next_target < number && next_target < at + count {
          rows.push(
            Element(
              element(
                "row",
                [
                  attribute("r", next_target.to_string()),
                  attribute("hidden", "1"),
                ],
                [],
              ),
            ),
          )
          changed += 1
          next_target += 1
        }
        if number >= at && number < at + count {
          let was_hidden = visible_row_state(row)
          if was_hidden != hide {
            changed += 1
            rows.push(
              Element({
                name: row.name,
                attributes: visible_row_attributes(row.attributes, hide),
                children: row.children,
              }),
            )
          } else {
            rows.push(node)
          }
          next_target = number + 1
        } else {
          rows.push(node)
        }
      }
      Element(_) =>
        raise InvalidWorkbook(
          "row visibility cannot preserve sheetData children",
        )
      _ => rows.push(node)
    }
  }
  while hide && next_target < at + count {
    rows.push(
      Element(
        element(
          "row",
          [attribute("r", next_target.to_string()), attribute("hidden", "1")],
          [],
        ),
      ),
    )
    changed += 1
    next_target += 1
  }
  if changed == 0 {
    return (archive, 0)
  }
  let updated = element(data.name, data.attributes, rows)
  let children : Array[@xml.Node] = []
  let mut found = false
  for node in worksheet.children {
    match node {
      Element(item) if item.local_name() == "sheetData" => {
        children.push(Element(updated))
        found = true
      }
      Element(item) if !found && comes_after_sheet_data(item.local_name()) => {
        children.push(Element(updated))
        children.push(node)
        found = true
      }
      _ => children.push(node)
    }
  }
  if !found {
    children.push(Element(updated))
  }
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
/// Hide one to 100 whole XLSX rows in a saved OPC copy. Sparse rows receive
/// row records with `hidden="1"`; cell values and styles stay in place.
pub fn hide_sheet_rows(
  archive : @opc.Package,
  sheet_name : String,
  at : Int32,
  count : Int32,
) -> (@opc.Package, Int32) raise XlsxError {
  set_sheet_rows_hidden(archive, sheet_name, at, count, true)
}

///|
/// Show one to 100 whole XLSX rows in a saved OPC copy. The changed count
/// includes only rows previously hidden; absent rows are left untouched.
pub fn show_sheet_rows(
  archive : @opc.Package,
  sheet_name : String,
  at : Int32,
  count : Int32,
) -> (@opc.Package, Int32) raise XlsxError {
  set_sheet_rows_hidden(archive, sheet_name, at, count, false)
}
