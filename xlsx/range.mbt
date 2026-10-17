///|
/// A bounded value-only selection. Rows include every position in the rectangle.
/// Formatting, date interpretation and formula caches are never imported.
pub(all) struct RangeValues {
  sheet_name : String
  range : @scene.CellRange
  rows : Array[Array[@scene.CellValue]]
  styled_cells : Int32
} derive(Debug, Eq)

///|
fn ranges_overlap(a : @scene.CellRange, b : @scene.CellRange) -> Bool {
  a.start_row <= b.end_row &&
  b.start_row <= a.end_row &&
  a.start_column <= b.end_column &&
  b.start_column <= a.end_column
}

///|
fn selected_position(
  range : @scene.CellRange,
  row : Int32,
  column : Int32,
) -> Bool {
  row >= range.start_row &&
  row <= range.end_row &&
  column >= range.start_column &&
  column <= range.end_column
}

///|
/// Read an exact, case-sensitive worksheet and uppercase A1 rectangle. Missing
/// positions remain Empty. Reject intersecting merges/formula ranges, selected
/// formulas/errors/unknown types, duplicate selected coordinates and malformed
/// coordinate structure. No workbook mutation or calculation occurs.
pub fn read_range(
  archive : @opc.Package,
  sheet_name~ : String,
  range~ : String,
) -> RangeValues raise XlsxError {
  guard parse_range_reference(range) is Some(bounds) else {
    raise InvalidCellReference(range)
  }
  let height = bounds.end_row - bounds.start_row + 1
  let width = bounds.end_column - bounds.start_column + 1
  if height > 10001 || width > 128 || height * width > 100000 {
    raise InvalidWorkbook(
      "selection exceeds 10001 rows, 128 columns or 100000 cells",
    )
  }
  let workbook = parse_part(archive, "xl/workbook.xml")
  if workbook.children_named("sheets").length() != 1 {
    raise InvalidWorkbook("expected one workbook sheets element")
  }
  let descriptors = workbook_sheets(workbook)
  let matches = descriptors.filter(s => s.name == sheet_name)
  if matches.is_empty() {
    raise SheetNotFound(sheet_name)
  }
  if matches.length() != 1 {
    raise InvalidWorkbook("ambiguous worksheet name: " + sheet_name)
  }
  let relationships = workbook_relationships(archive)
  let ids : Map[String, Bool] = Map([])
  for relationship in relationships {
    if ids.contains(relationship.id) {
      raise InvalidWorkbook(
        "duplicate workbook relationship id: " + relationship.id,
      )
    }
    ids[relationship.id] = true
  }
  let part = worksheet_part_name(relationships, matches[0])
  let root = parse_part(archive, part)
  if root.local_name() != "worksheet" ||
    root.children_named("sheetData").length() > 1 ||
    root.children_named("mergeCells").length() > 1 {
    raise InvalidWorkbook(
      "invalid worksheet or repeated sheetData/mergeCells: " + part,
    )
  }
  for merged in parse_merged_ranges(root) {
    if ranges_overlap(bounds, merged) {
      raise InvalidWorkbook("selected range intersects merged cells")
    }
  }
  let strings = shared_strings(
    resolved_metadata_part(
      archive, relationships, shared_strings_relationship_types,
    ),
  )
  let rows = Array::makei(height, _ => {
    Array::make(width, @scene.CellValue::Empty)
  })
  let seen : Map[String, Bool] = Map([])
  let mut styled_cells = 0
  let mut units = 0
  let mut previous_row = 0
  for data in root.children_named("sheetData") {
    for row_element in data.children_named("row") {
      let row = match row_element.attribute("r") {
        None => previous_row + 1
        Some(text) =>
          match parse_decimal(text, max_row) {
            Some(value) if value > 0 => value
            _ => raise InvalidWorkbook("invalid row coordinate: " + text)
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
        if c > max_column {
          raise InvalidCoordinates(row=r, column=c)
        }
        previous_column = c
        // Array/data-table formula followers may have a cache but no local <f>.
        for formula in cell.children_named("f") {
          if formula.attribute("ref") is Some(reference) {
            guard parse_range_reference(reference) is Some(formula_range) else {
              raise InvalidCellReference(reference)
            }
            if ranges_overlap(bounds, formula_range) {
              raise InvalidWorkbook(
                "selection intersects formula range: " + reference,
              )
            }
          }
        }
        if !selected_position(bounds, r, c) {
          continue
        }
        let reference = cell_reference(r, c)
        if seen.contains(reference) {
          raise InvalidWorkbook("duplicate selected coordinate: " + reference)
        }
        seen[reference] = true
        if !cell.children_named("f").is_empty() {
          raise InvalidWorkbook("formula selected at " + reference)
        }
        if cell.children_named("v").length() > 1 ||
          cell.children_named("is").length() > 1 {
          raise InvalidWorkbook("ambiguous selected value at " + reference)
        }
        match cell.attribute("t") {
          None | Some("n" | "s" | "str" | "inlineStr" | "b") => ()
          Some(kind) =>
            raise InvalidWorkbook(
              "unsupported selected cell type " + kind + " at " + reference,
            )
        }
        if cell.attribute("t") == Some("inlineStr") {
          if !cell.children_named("v").is_empty() {
            raise InvalidWorkbook(
              "inline string contains conflicting value at " + reference,
            )
          }
        } else if !cell.children_named("is").is_empty() {
          raise InvalidWorkbook(
            "non-inline cell contains inline string at " + reference,
          )
        }
        let value = parse_cell_value(cell, strings)
        match value {
          Number(text) => {
            let parsed = @json.parse(text) catch {
              _ =>
                raise InvalidWorkbook("invalid selected number at " + reference)
            }
            guard parsed is Number(number, ..) &&
              !number.is_inf() &&
              !number.is_nan() &&
              text == text.trim().to_owned() else {
              raise InvalidWorkbook(
                "expected finite JSON number at " + reference,
              )
            }
            units += text.length()
          }
          Text(text) => units += text.length()
          _ => ()
        }
        if units > 4000000 {
          raise InvalidWorkbook("selection exceeds 4000000 text units")
        }
        if cell.attribute("s") is Some(_) {
          styled_cells += 1
        }
        rows[r - bounds.start_row][c - bounds.start_column] = value
      }
    }
  }
  { sheet_name, range: bounds, rows, styled_cells, }
}

///|
pub extend RangeValues with Eq::{equal, not_equal}

///|
pub extend RangeValues with @debug.Debug::{to_repr}
