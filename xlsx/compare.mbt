///|
/// Supported cell content at one coordinate. A formula's value is its stored
/// cache, never a computed result. None differs from an explicit empty string.
pub(all) struct ComparisonCell {
  row : Int32
  column : Int32
  value_type : String
  value : String?
  formula : String?
  formula_attributes : Map[String, String]
} derive(Debug, Eq)

///|
pub(all) struct CellDifference {
  address : String
  before : ComparisonCell?
  after : ComparisonCell?
  changes : Array[String]
} derive(Debug, Eq)

///|
pub(all) struct SheetDifference {
  name : String
  before_position : Int32?
  after_position : Int32?
  before_state : String?
  after_state : String?
  before_merges : Array[String]
  after_merges : Array[String]
  changes : Array[String]
  cells : Array[CellDifference]
} derive(Debug, Eq)

///|
pub(all) struct WorkbookComparison {
  before_sheets : Array[String]
  after_sheets : Array[String]
  sheets : Array[SheetDifference]
  changed_cells : Int32
  before_date1904 : Bool
  after_date1904 : Bool
  date_system_changed : Bool
  warnings : Array[String]
} derive(Debug, Eq)

///|
fn compare_cells(
  before : Map[String, ComparisonCell],
  after : Map[String, ComparisonCell],
) -> Array[CellDifference] {
  let addresses : Map[String, ComparisonCell] = Map([])
  for address, cell in before {
    addresses[address] = cell
  }
  for address, cell in after {
    addresses[address] = cell
  }
  let ordered = addresses.values().to_array()
  ordered.sort_by((a, b) => {
    if a.row == b.row {
      a.column.compare(b.column)
    } else {
      a.row.compare(b.row)
    }
  })
  let result = []
  for cell in ordered {
    let address = cell_reference(cell.row, cell.column)
    let old = before.get(address)
    let new = after.get(address)
    let changes : Array[String] = []
    match (old, new) {
      (None, Some(_)) => changes.push("added")
      (Some(_), None) => changes.push("removed")
      (Some(a), Some(b)) => {
        if a.formula != b.formula {
          changes.push("formula")
        }
        if a.formula_attributes != b.formula_attributes {
          changes.push("formula_metadata")
        }
        if a.value != b.value || a.value_type != b.value_type {
          changes.push(
            if a.formula is Some(_) && b.formula is Some(_) {
              "cached_value"
            } else {
              "value"
            },
          )
        }
      }
      _ => ()
    }
    if !changes.is_empty() {
      result.push({ address, before: old, after: new, changes, })
    }
  }
  result
}

///|
/// Compare supported workbook content by exact sheet name and A1 coordinate.
/// Does not align inserted rows, calculate formulas, compare visual formatting,
/// or establish semantic/package equivalence when no changes are reported.
pub fn compare_workbooks(
  before : @opc.Package,
  after : @opc.Package,
) -> WorkbookComparison raise XlsxError {
  let before_date1904 = comparison_date1904(before)
  let after_date1904 = comparison_date1904(after)
  let original = comparison_sheets(before)
  let copy = comparison_sheets(after)
  let old : Map[String, ComparisonSheet] = Map([])
  let new : Map[String, ComparisonSheet] = Map([])
  let names : Array[String] = []
  for sheet in original {
    old[sheet.name] = sheet
    names.push(sheet.name)
  }
  for sheet in copy {
    new[sheet.name] = sheet
    if !old.contains(sheet.name) {
      names.push(sheet.name)
    }
  }
  let sheets = []
  let mut changed_cells = 0
  for name in names {
    let a = old.get(name)
    let b = new.get(name)
    let before_position = a.map(s => s.position)
    let after_position = b.map(s => s.position)
    let before_state = a.map(s => s.state)
    let after_state = b.map(s => s.state)
    let before_merges = a.map(s => s.merges).unwrap_or([])
    let after_merges = b.map(s => s.merges).unwrap_or([])
    let cells = compare_cells(
      a.map(s => s.cells).unwrap_or(Map([])),
      b.map(s => s.cells).unwrap_or(Map([])),
    )
    let changes : Array[String] = []
    if a is None {
      changes.push("added")
    } else if b is None {
      changes.push("removed")
    } else {
      if before_position != after_position {
        changes.push("position")
      }
      if before_state != after_state {
        changes.push("visibility")
      }
      if before_merges != after_merges {
        changes.push("merges")
      }
    }
    if !cells.is_empty() {
      changes.push("cells")
    }
    changed_cells += cells.length()
    if !changes.is_empty() {
      sheets.push({
        name,
        before_position,
        after_position,
        before_state,
        after_state,
        before_merges,
        after_merges,
        changes,
        cells,
      })
    }
  }
  {
    before_sheets: original.map(s => s.name),
    after_sheets: copy.map(s => s.name),
    sheets,
    changed_cells,
    before_date1904,
    after_date1904,
    date_system_changed: before_date1904 != after_date1904,
    warnings: [
      "Comparison includes direct worksheet sheetData/row/c content and matches exact case-sensitive sheet names and A1 coordinates. Wrapped or extension content is outside this view. Inserted rows and renamed sheets are not aligned; hidden sheets and cells are included.",
      "Formula expressions, formula attributes and stored caches are compared independently. Shared formulas are not expanded, external references are not followed and nothing is recalculated; cache freshness is unknown.",
      "Text is flattened and numeric/date tokens are compared exactly. Explicit empty cells differ from absent cells. Styles, number formats, rich text formatting, charts, comments, hyperlinks, filters, drawings and other package content are not compared.",
      "No reported content change does not mean identical files, full Office fidelity, print readiness, delivery or customer acceptance. Retain and inspect both source files.",
    ],
  }
}

///|
pub extend ComparisonCell with Debug::{to_repr}

///|
pub extend ComparisonCell with Eq::{not_equal, equal}

///|
pub extend CellDifference with Debug::{to_repr}

///|
pub extend CellDifference with Eq::{not_equal, equal}

///|
pub extend SheetDifference with Debug::{to_repr}

///|
pub extend SheetDifference with Eq::{not_equal, equal}

///|
pub extend WorkbookComparison with Debug::{to_repr}

///|
pub extend WorkbookComparison with Eq::{not_equal, equal}
