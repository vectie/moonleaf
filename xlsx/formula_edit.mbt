///|
fn value_edit_worksheet(
  archive : @opc.Package,
  sheet_name : String,
  row : Int32,
  column : Int32,
) -> (String, @xml.Element) raise XlsxError {
  if row < 1 || row > max_row || column < 1 || column > max_column {
    raise InvalidCoordinates(row~, column~)
  }
  let workbook = parse_part(archive, "xl/workbook.xml")
  guard descriptor_named(workbook_sheets(workbook), sheet_name)
    is Some(descriptor) else {
    raise SheetNotFound(sheet_name)
  }
  let part = worksheet_part_name(workbook_relationships(archive), descriptor)
  let root = parse_part(archive, part)
  for range in parse_merged_ranges(root) {
    if row >= range.start_row &&
      row <= range.end_row &&
      column >= range.start_column &&
      column <= range.end_column &&
      (row != range.start_row || column != range.start_column) {
      raise InvalidWorkbook("value edit targets a non-anchor merged cell")
    }
  }
  if root.first_child("sheetData") is Some(data) &&
    cell_location(data, row, column) is Some((ri, ci)) {
    guard data.children[ri] is Element(existing_row) &&
      existing_row.children[ci] is Element(cell) else {
      raise InvalidWorkbook("target cell is missing")
    }
    if cell.first_child("f") is Some(formula) && !formula.attributes.is_empty() {
      raise InvalidWorkbook(
        "shared, array and data-table formula edits are unsupported",
      )
    }
  }
  (part, root)
}

///|
fn formula_cell_element(
  root : @xml.Element,
  reference : String,
  expression : String,
) -> @xml.Element {
  if root.local_name() == "c" && root.attribute("r") == Some(reference) {
    let prefix = root.name.strip_suffix("c").unwrap_or("").to_owned()
    {
      name: root.name,
      attributes: root.attributes.filter(item => item.name != "t"),
      children: [
        Element({
          name: prefix + "f",
          attributes: [],
          children: [Text(expression)],
        }),
      ],
    }
  } else {
    {
      ..root,
      children: root.children.map(child => {
        match child {
          Element(element) =>
            Element(formula_cell_element(element, reference, expression))
          Text(_) => child
        }
      }),
    }
  }
}

///|
/// Replace one ordinary cell with a supported formula and recalculate the
/// completed workbook. Coordinates/styles and unrelated OPC parts survive;
/// shared/array/data-table formulas, unsupported syntax and cycles fail closed.
pub fn set_cell_formula(
  archive : @opc.Package,
  sheet_name : String,
  row : Int32,
  column : Int32,
  formula : String,
) -> @opc.Package raise XlsxError {
  let expression = formula
    .trim()
    .to_owned()
    .strip_prefix("=")
    .unwrap_or(formula.trim())
    .to_owned()
  if expression.is_empty() ||
    expression.length() > 2048 ||
    !valid_xml_cell_text(expression) {
    raise InvalidWorkbook(
      "formula must be valid XML text of 1 to 2048 characters",
    )
  }
  let (part, _) = value_edit_worksheet(archive, sheet_name, row, column)
  let inserted = set_cell_text(archive, sheet_name, row, column, "")
  let root = parse_part(inserted, part)
  recalculate(
    inserted.replace_text(
      part,
      @xml.serialize(
        formula_cell_element(root, cell_reference(row, column), expression),
      ),
    ),
  )
}

///|
/// Typed value editing for interactive callers. The legacy text/session APIs
/// retain their existing semantics; this API permits replacing ordinary formula
/// cells and always recomputes supported caches before returning a copy.
pub fn set_cell_value(
  archive : @opc.Package,
  sheet_name : String,
  row : Int32,
  column : Int32,
  value_type : String,
  value : String,
) -> @opc.Package raise XlsxError {
  if value.length() > 32768 {
    raise InvalidWorkbook("cell value exceeds 32768 characters")
  }
  if value_type == "formula" {
    return set_cell_formula(archive, sheet_name, row, column, value)
  }
  ignore(value_edit_worksheet(archive, sheet_name, row, column))
  let edited = match value_type {
    "text" => set_cell_text(archive, sheet_name, row, column, value)
    "number" => {
      let number = @string.parse_double(value.trim()) catch {
        _ => raise InvalidWorkbook("invalid numeric cell value")
      }
      set_cell_number(archive, sheet_name, row, column, formula_finite(number))
    }
    _ => raise InvalidWorkbook("value_type must be text, number or formula")
  }
  recalculate(edited)
}
