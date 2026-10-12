///|
fn[T : ToJson] optional_json(value : T?) -> Json {
  match value {
    Some(v) => v.to_json()
    None => Json::null()
  }
}

///|
fn comparison_cell_json(cell : ComparisonCell?) -> Json {
  match cell {
    None => Json::null()
    Some(c) =>
      {
        "row": c.row,
        "column": c.column,
        "value_type": c.value_type,
        "value": optional_json(c.value),
        "formula": optional_json(c.formula),
        "formula_attributes": c.formula_attributes,
      }
  }
}

///|
/// Stable JSON projection: absent snapshots and optional fields are JSON null,
/// not the general MoonBit Option encoding. Numeric tokens remain strings.
pub fn WorkbookComparison::to_json(self : WorkbookComparison) -> Json {
  let sheets = self.sheets.map(s => {
    let cells = s.cells.map(c => {
      let value : Json = {
        "address": c.address,
        "before": comparison_cell_json(c.before),
        "after": comparison_cell_json(c.after),
        "changes": c.changes,
      }
      value
    })
    let value : Json = {
      "name": s.name,
      "before_position": optional_json(s.before_position),
      "after_position": optional_json(s.after_position),
      "before_state": optional_json(s.before_state),
      "after_state": optional_json(s.after_state),
      "before_merges": s.before_merges,
      "after_merges": s.after_merges,
      "changes": s.changes,
      "cells": cells,
    }
    value
  })
  {
    "before_sheets": self.before_sheets,
    "after_sheets": self.after_sheets,
    "sheets": sheets,
    "changed_cells": self.changed_cells,
    "before_date1904": self.before_date1904,
    "after_date1904": self.after_date1904,
    "date_system_changed": self.date_system_changed,
    "warnings": self.warnings,
  }
}
