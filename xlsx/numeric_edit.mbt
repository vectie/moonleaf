///|
fn numeric_cell_element(
  root : @xml.Element,
  reference : String,
  value : Double,
) -> @xml.Element {
  if root.local_name() == "c" && root.attribute("r") == Some(reference) {
    let prefix = root.name.strip_suffix("c").unwrap_or("").to_owned()
    {
      name: root.name,
      attributes: root.attributes.filter(attribute => attribute.name != "t"),
      children: [
        Element({
          name: prefix + "v",
          attributes: [],
          children: [Text(value.to_string())],
        }),
      ],
    }
  } else {
    {
      name: root.name,
      attributes: root.attributes,
      children: root.children.map(child => {
        match child {
          Element(element) =>
            Element(numeric_cell_element(element, reference, value))
          Text(_) => child
        }
      }),
    }
  }
}

///|
/// Store a finite numeric value, preserving the target cell's style. Like
/// set_cell_text this does not recalculate dependent formulas; call recalculate
/// on the completed batch before consuming formula caches.
pub fn set_cell_number(
  archive : @opc.Package,
  sheet_name : String,
  row : Int,
  column : Int,
  value : Double,
) -> @opc.Package raise XlsxError {
  let value = formula_finite(value)
  let edited = set_cell_text(
    archive,
    sheet_name,
    row,
    column,
    value.to_string(),
  )
  let workbook = parse_part(edited, "xl/workbook.xml")
  guard descriptor_named(workbook_sheets(workbook), sheet_name)
    is Some(descriptor) else {
    raise SheetNotFound(sheet_name)
  }
  let part = worksheet_part_name(workbook_relationships(edited), descriptor)
  let root = parse_part(edited, part)
  edited.replace_text(
    part,
    @xml.serialize(
      numeric_cell_element(root, cell_reference(row, column), value),
    ),
  )
}
