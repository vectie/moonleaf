///|
priv struct ComparisonSheet {
  name : String
  position : Int32
  state : String
  merges : Array[String]
  cells : Map[String, ComparisonCell]
}

///|
fn comparison_value(
  cell : @xml.Element,
  strings : Array[String],
) -> (String, String?) raise XlsxError {
  let value = parse_cell_value(cell, strings)
  if cell.first_child("f") is Some(_) {
    let kind = match cell.attribute("t") {
      None | Some("n") => "number"
      Some("str") => "text"
      Some("b") => "boolean"
      Some("e") => "error"
      Some(other) =>
        raise InvalidWorkbook("unsupported formula cache type: " + other)
    }
    return (kind, child_text(cell, "v"))
  }
  match value {
    Empty => ("empty", None)
    Text(text) =>
      if cell.attribute("t") == Some("d") {
        ("date", Some(text))
      } else {
        ("text", Some(text))
      }
    Number(text) => ("number", Some(text))
    Boolean(value) => ("boolean", Some(if value { "true" } else { "false" }))
    Error(text) => ("error", Some(text))
    Formula(..) => raise InvalidWorkbook("unexpected formula projection")
  }
}

///|
fn comparison_sheets(
  archive : @opc.Package,
) -> Array[ComparisonSheet] raise XlsxError {
  let workbook = parse_part(archive, "xl/workbook.xml")
  if workbook.children_named("sheets").length() != 1 {
    raise InvalidWorkbook("comparison requires one sheets element")
  }
  let descriptors = workbook_sheets(workbook)
  if descriptors.length() > 100 {
    raise InvalidWorkbook("comparison exceeds 100 sheets per workbook")
  }
  let relationships = workbook_relationships(archive)
  let ids : Map[String, Bool] = Map([])
  for relationship in relationships {
    if ids.contains(relationship.id) {
      raise InvalidWorkbook("duplicate workbook relationship id")
    }
    ids[relationship.id] = true
  }
  let strings = shared_strings(
    resolved_metadata_part(
      archive, relationships, shared_strings_relationship_types,
    ),
  )
  let names : Map[String, Bool] = Map([])
  let parts : Map[String, Bool] = Map([])
  let result = []
  let mut count = 0
  let mut units = 0
  let mut merge_count = 0
  let sheet_elements = workbook
    .first_child("sheets")
    .unwrap()
    .children_named("sheet")
  for index, descriptor in descriptors {
    if descriptor.name == "" || names.contains(descriptor.name) {
      raise InvalidWorkbook("empty or duplicate worksheet name")
    }
    names[descriptor.name] = true
    let part = worksheet_part_name(relationships, descriptor)
    if parts.contains(part) {
      raise InvalidWorkbook("worksheets alias the same part")
    }
    parts[part] = true
    let root = parse_part(archive, part)
    if root.local_name() != "worksheet" ||
      root.children_named("sheetData").length() > 1 ||
      root.children_named("mergeCells").length() > 1 {
      raise InvalidWorkbook("ambiguous worksheet comparison structure")
    }
    let state = sheet_elements[index].attribute("state").unwrap_or("visible")
    if state != "visible" && state != "hidden" && state != "veryHidden" {
      raise InvalidWorkbook("unknown worksheet visibility")
    }
    let merges = parse_merged_ranges(root).map(r => {
      cell_reference(r.start_row, r.start_column) +
      ":" +
      cell_reference(r.end_row, r.end_column)
    })
    merge_count += merges.length()
    if merge_count > 10000 {
      raise InvalidWorkbook("comparison exceeds 10000 merged ranges")
    }
    merges.sort()
    let cells : Map[String, ComparisonCell] = Map([])
    let mut previous_row = 0
    for data in root.children_named("sheetData") {
      for row_element in data.children_named("row") {
        let row = match row_element.attribute("r") {
          None => previous_row + 1
          Some(text) =>
            match parse_decimal(text, max_row) {
              Some(value) if value > 0 => value
              _ => raise InvalidWorkbook("invalid comparison row coordinate")
            }
        }
        if row > max_row {
          raise InvalidCoordinates(row~, column=1)
        }
        previous_row = row
        let mut previous_column = 0
        for cell in row_element.children_named("c") {
          let (r, c) = match cell.attribute("r") {
            None => (row, previous_column + 1)
            Some(reference) =>
              match parse_cell_reference(reference) {
                Some(position) => position
                None => raise InvalidCellReference(reference)
              }
          }
          if r != row || c > max_column {
            raise InvalidWorkbook(
              "cell and row coordinates disagree or exceed bounds",
            )
          }
          previous_column = c
          let address = cell_reference(r, c)
          if cells.contains(address) {
            raise InvalidWorkbook("duplicate comparison cell: " + address)
          }
          count += 1
          if count > 100000 {
            raise InvalidWorkbook(
              "comparison exceeds 100000 explicit cells per workbook",
            )
          }
          if cell.children_named("f").length() > 1 ||
            cell.children_named("v").length() > 1 ||
            cell.children_named("is").length() > 1 {
            raise InvalidWorkbook("ambiguous comparison cell payload")
          }
          match cell.attribute("t") {
            None | Some("n" | "s" | "str" | "inlineStr" | "b" | "e" | "d") => ()
            Some(other) =>
              raise InvalidWorkbook(
                "unsupported comparison cell type: " + other,
              )
          }
          if cell.attribute("t") == Some("inlineStr") {
            if cell.first_child("v") is Some(_) ||
              cell.first_child("f") is Some(_) {
              raise InvalidWorkbook("conflicting inline string payload")
            }
          } else if cell.first_child("is") is Some(_) {
            raise InvalidWorkbook("non-inline cell contains inline string")
          }
          let (value_type, value) = comparison_value(cell, strings)
          let formula = child_text(cell, "f")
          let attributes : Map[String, String] = Map([])
          if cell.first_child("f") is Some(f) {
            for attribute in f.attributes {
              attributes[attribute.name] = attribute.value
              units += attribute.name.length() + attribute.value.length()
            }
          }
          units += descriptor.name.length() +
            value.unwrap_or("").length() +
            formula.unwrap_or("").length()
          if units > 4000000 {
            raise InvalidWorkbook(
              "comparison exceeds 4000000 text units per workbook",
            )
          }
          cells[address] = {
            row: r,
            column: c,
            value_type,
            value,
            formula,
            formula_attributes: attributes,
          }
        }
      }
    }
    result.push({
      name: descriptor.name,
      position: index + 1,
      state,
      merges,
      cells,
    })
  }
  result
}

///|
fn comparison_date1904(archive : @opc.Package) -> Bool raise XlsxError {
  let root = parse_part(archive, "xl/workbook.xml")
  if root.children_named("workbookPr").length() > 1 {
    raise InvalidWorkbook("ambiguous workbook date system")
  }
  let date1904 = match root.first_child("workbookPr") {
    Some(p) => p.attribute("date1904")
    None => None
  }
  match date1904 {
    None | Some("0" | "false") => false
    Some("1" | "true") => true
    _ => raise InvalidWorkbook("invalid workbook date system")
  }
}
