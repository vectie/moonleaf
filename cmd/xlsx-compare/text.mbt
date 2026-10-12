///|
fn optional_text(value : String?) -> String {
  match value {
    Some(v) => v.to_json().stringify()
    None => "(none)"
  }
}

///|
fn optional_int(value : Int?) -> String {
  match value {
    Some(v) => v.to_string()
    None => "(none)"
  }
}

///|
fn display_cell(cell : @xlsx.ComparisonCell?) -> String {
  match cell {
    None => "(absent)"
    Some(cell) => {
      let value = optional_text(cell.value)
      match cell.formula {
        Some(formula) => {
          let expression = formula.to_json().stringify()
          let attributes = cell.formula_attributes.to_json().stringify()
          "formula " +
          expression +
          " attributes=" +
          attributes +
          "; stored " +
          cell.value_type +
          " cache=" +
          value
        }
        None => cell.value_type + " " + value
      }
    }
  }
}

///|
fn text_report(
  comparison : @xlsx.WorkbookComparison,
  before_hash : String,
  after_hash : String,
  identical : Bool,
) -> String {
  let lines = [
    "MoonLeaf workbook comparison (supported content only)",
    "Original SHA-256: " + before_hash,
    "Copy SHA-256:     " + after_hash,
    "Identical bytes: \{identical}",
    "Original sheets: " + comparison.before_sheets.to_json().stringify(),
    "Copy sheets:     " + comparison.after_sheets.to_json().stringify(),
    "Changed cells: \{comparison.changed_cells}",
  ]
  if comparison.date_system_changed {
    lines.push(
      "Workbook date1904: \{comparison.before_date1904} -> \{comparison.after_date1904}",
    )
  }
  for sheet in comparison.sheets {
    lines.push("")
    lines.push(
      "Sheet " +
      sheet.name.to_json().stringify() +
      ": " +
      sheet.changes.join(", "),
    )
    lines.push(
      "  Position: " +
      optional_int(sheet.before_position) +
      " -> " +
      optional_int(sheet.after_position),
    )
    lines.push(
      "  Visibility: " +
      optional_text(sheet.before_state) +
      " -> " +
      optional_text(sheet.after_state),
    )
    if sheet.before_merges != sheet.after_merges {
      lines.push(
        "  Merges: " +
        sheet.before_merges.to_json().stringify() +
        " -> " +
        sheet.after_merges.to_json().stringify(),
      )
    }
    for cell in sheet.cells {
      lines.push("  " + cell.address + " [" + cell.changes.join(", ") + "]")
      lines.push("    before: " + display_cell(cell.before))
      lines.push("    after:  " + display_cell(cell.after))
    }
  }
  if comparison.sheets.is_empty() && !comparison.date_system_changed {
    lines.push(
      "No differences in the compared content. See scope limits below.",
    )
  }
  lines.push("")
  lines.push("Scope limits:")
  for warning in comparison.warnings {
    lines.push("- " + warning)
  }
  lines.join("\n")
}
