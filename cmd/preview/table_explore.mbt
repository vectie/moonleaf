///|
/// Use the same Leaf reader and typed table export as MoonDesk's explorer.
/// The first worksheet row supplies labels. Blank or repeated labels receive
/// stable unique names so both index and header selectors remain unambiguous.
fn explore_sheet_table(sheet : @scene.Sheet) -> @jsontable.Table {
  let mut height = 0
  let mut width = 0
  for cell in sheet.cells {
    height = height.max(cell.row)
    width = width.max(cell.column)
  }
  if height > 100_000 ||
    width > 1_000 ||
    height.to_int64() * width.to_int64() > 1_000_000L {
    abort(
      "table exploration exceeds 100000 rows, 1000 columns or 1000000 cells",
    )
  }
  let rows : Array[Array[@scene.CellValue]] = Array::makei(height, _ => {
    Array::make(width, Empty)
  })
  for cell in sheet.cells {
    if cell.row > 0 && cell.column > 0 {
      rows[cell.row - 1][cell.column - 1] = match cell.value {
        Formula(cached=Some(value), ..) => Text(value)
        Formula(cached=None, ..) => Empty
        Error(value) => Text(value)
        value => value
      }
    }
  }
  if rows.is_empty() {
    return { columns: [], rows: [], }
  }
  let columns : Array[String] = []
  for i, value in rows[0] {
    let label = cell_text(value)
    let base = if label == "" { "Column \{i + 1}" } else { label }
    let mut name = base
    let mut suffix = 2
    while columns.contains(name) {
      name = base + " (\{suffix})"
      suffix += 1
    }
    columns.push(name)
  }
  { columns, rows: rows[1:].to_owned(), }
}

///|
fn explore_string(
  fields : Map[String, Json],
  key : String,
  fallback? : String = "",
) -> String {
  match fields.get(key) {
    None | Some(Null) => fallback
    Some(String(value)) => value
    _ => abort("table exploration \{key} must be a string")
  }
}

///|
fn explore_integer(
  fields : Map[String, Json],
  key : String,
  fallback : Int,
  maximum : Int,
) -> Int {
  match fields.get(key) {
    None | Some(Null) => fallback
    Some(Number(value, ..)) if value >= 0 &&
      value <= maximum.to_double() &&
      value == value.to_int().to_double() => value.to_int()
    _ =>
      abort("table exploration \{key} must be an integer from 0 to \{maximum}")
  }
}

///|
fn explore_column(
  fields : Map[String, Json],
  key : String,
  columns : Array[String],
) -> Int? {
  match fields.get(key) {
    None | Some(Null) | Some(String("")) => None
    Some(Number(value, ..)) if value >= 0 &&
      value < columns.length().to_double() &&
      value == value.to_int().to_double() => Some(value.to_int())
    Some(String(name)) => {
      for i, column in columns {
        if name == column {
          return Some(i)
        }
      }
      for i in 0..<columns.length() {
        if name == i.to_string() {
          return Some(i)
        }
      }
      abort("unknown table exploration column for \{key}: \{name}")
    }
    _ =>
      abort("table exploration \{key} needs a zero-based index or exact header")
  }
}

///|
fn explore_number(text : String) -> Double? {
  let value = @json.parse(text.trim().to_owned()) catch { _ => return None }
  match value {
    Number(value, ..) if !value.is_nan() && !value.is_inf() => Some(value)
    _ => None
  }
}

///|
fn explore_bound(fields : Map[String, Json], key : String) -> Double? {
  match fields.get(key) {
    None | Some(Null) | Some(String("")) => None
    Some(Number(value, ..)) if !value.is_nan() && !value.is_inf() => Some(value)
    Some(String(text)) =>
      match explore_number(text) {
        Some(value) => Some(value)
        None => abort("table exploration \{key} must be a finite JSON number")
      }
    _ => abort("table exploration \{key} must be a finite JSON number")
  }
}

///|
/// UTF-16 lexical ordering, with worksheet row order as the final tie-breaker.
fn explore_compare(left : String, right : String) -> Int {
  for i in 0..<left.length().min(right.length()) {
    let order = left.code_unit_at(i).compare(right.code_unit_at(i))
    if order != 0 {
      return order
    }
  }
  left.length().compare(right.length())
}

///|
fn explore_indexes(
  table : @jsontable.Table,
  fields : Map[String, Json],
) -> Array[Int] {
  let text_column = explore_column(fields, "text_column", table.columns)
  let needle = explore_string(fields, "contains").to_lower()
  let number_column = explore_column(fields, "number_column", table.columns)
  let minimum = explore_bound(fields, "min")
  let maximum = explore_bound(fields, "max")
  if needle != "" && text_column is None {
    abort("choose a text filter column")
  }
  if (minimum is Some(_) || maximum is Some(_)) && number_column is None {
    abort("choose a numeric filter column")
  }
  if minimum is Some(a) && maximum is Some(b) && a > b {
    abort("minimum must not exceed maximum")
  }
  let rows = table.text_rows()
  let indexes : Array[Int] = []
  for i, row in rows {
    if text_column is Some(column) && !row[column].to_lower().contains(needle) {
      continue
    }
    if number_column is Some(column) &&
      (minimum is Some(_) || maximum is Some(_)) {
      guard explore_number(row[column]) is Some(value) else { continue }
      if minimum is Some(bound) && value < bound {
        continue
      }
      if maximum is Some(bound) && value > bound {
        continue
      }
    }
    indexes.push(i)
  }
  let sort = explore_column(fields, "sort", table.columns)
  let sort_type = explore_string(fields, "sort_type", fallback="text")
  let direction = explore_string(fields, "direction", fallback="asc")
  if !["text", "number"].contains(sort_type) ||
    !["asc", "desc"].contains(direction) {
    abort("sort_type needs text/number and direction needs asc/desc")
  }
  if sort is Some(column) {
    indexes.sort_by((a, b) => {
      let left = rows[a][column]
      let right = rows[b][column]
      let comparison = if sort_type == "number" {
        match (explore_number(left), explore_number(right)) {
          (Some(a), Some(b)) =>
            if direction == "desc" {
              b.compare(a)
            } else {
              a.compare(b)
            }
          (Some(_), None) => -1
          (None, Some(_)) => 1
          (None, None) => 0
        }
      } else if direction == "desc" {
        explore_compare(right, left)
      } else {
        explore_compare(left, right)
      }
      if comparison == 0 {
        a.compare(b)
      } else {
        comparison
      }
    })
  }
  indexes
}

///|
/// Match MoonDesk: blank/non-numeric amounts are excluded from numeric counts
/// and totals; groups retain first appearance after filtering and sorting.
fn explore_summary(
  table : @jsontable.Table,
  group : Int?,
  sum : Int?,
) -> (@jsontable.Table, Json) {
  let groups : Map[String, (Int, Int, Double)] = Map([])
  let mut numeric_values = 0
  let mut total = 0.0
  for row in table.text_rows() {
    let key = match group {
      Some(column) => row[column]
      None => ""
    }
    let (count, numeric, previous) = groups.get(key).unwrap_or((0, 0, 0.0))
    let number = match sum {
      Some(column) => explore_number(row[column])
      None => None
    }
    groups[key] = match number {
      Some(value) => {
        numeric_values += 1
        total += value
        (count + 1, numeric + 1, previous + value)
      }
      None => (count + 1, numeric, previous)
    }
  }
  let columns : Array[String] = []
  if group is Some(column) {
    columns.push("Group: " + table.columns[column])
  }
  columns.push("Rows")
  if sum is Some(column) {
    columns.push("Numeric values: " + table.columns[column])
    columns.push("Sum: " + table.columns[column])
  }
  let rows : Array[Array[@scene.CellValue]] = []
  for key, (count, numeric, value) in groups {
    let row : Array[@scene.CellValue] = []
    if group is Some(_) {
      row.push(Text(key))
    }
    row.push(Number(count.to_string()))
    if sum is Some(_) {
      row.push(Number(numeric.to_string()))
      row.push(
        if numeric == 0 {
          Empty
        } else if value.is_nan() || value.is_inf() {
          Text("Overflow")
        } else {
          Number(value.to_string())
        },
      )
    }
    rows.push(row)
  }
  let sum_value : Json = if numeric_values == 0 ||
    total.is_nan() ||
    total.is_inf() {
    Json::null()
  } else {
    Json::number(total)
  }
  let totals : Json = {
    "rows": table.rows.length(),
    "numeric_values": numeric_values,
    "sum": sum_value,
    "overflow": total.is_nan() || total.is_inf(),
  }
  ({ columns, rows, }, totals)
}

///|
fn table_explore(args : Array[String]) -> Unit {
  if args.length() != 5 && args.length() != 6 {
    abort("usage: moonleaf-preview table-explore SOURCE DISPLAY_NAME [OUTPUT]")
  }
  let raw = read_stdin()
  if raw.length() > 65_536 {
    abort("table exploration request exceeds 65536 code units")
  }
  let request = @json.parse(raw) catch {
    _ => abort("invalid table exploration JSON")
  }
  guard request is Object(fields) else {
    abort("table exploration request must be an object")
  }
  let filename = args[4]
  let lower = filename.to_lower()
  if !lower.has_suffix(".csv") &&
    !lower.has_suffix(".tsv") &&
    !lower.has_suffix(".xlsx") {
    abort("table exploration supports CSV, TSV or XLSX")
  }
  let document = @moonleaf.open(filename, read_file(args[3])) catch {
    error => abort("MoonLeaf table open failed: \{Repr(error)}")
  }
  guard document is WorkbookDocument(workbook) else {
    abort("MoonLeaf did not return a workbook")
  }
  guard !workbook.sheets.is_empty() else { abort("workbook has no worksheet") }
  let names = workbook.sheets.map(sheet => sheet.name)
  let sheet_name = explore_string(fields, "sheet", fallback=names[0])
  let sheet_name = if sheet_name == "" { names[0] } else { sheet_name }
  guard workbook.sheets.iter().find_first(sheet => sheet.name == sheet_name)
    is Some(sheet) else {
    abort("unknown workbook sheet: \{sheet_name}")
  }
  let table = explore_sheet_table(sheet)
  let indexes = explore_indexes(table, fields)
  let selected : @jsontable.Table = {
    columns: table.columns,
    rows: indexes.map(i => table.rows[i]),
  }
  let group = explore_column(fields, "group", table.columns)
  let sum = explore_column(fields, "sum", table.columns)
  let (summary, totals) = explore_summary(selected, group, sum)
  let offset = explore_integer(fields, "offset", 0, 100_000).min(
    indexes.length(),
  )
  let limit = explore_integer(fields, "limit", 200, 1_000)
  let end = (offset + limit).min(indexes.length())
  let page : @jsontable.Table = {
    columns: selected.columns,
    rows: selected.rows[offset:end].to_owned(),
  }
  let summary_count = summary.rows.length()
  let summary_page : @jsontable.Table = {
    columns: summary.columns,
    rows: summary.rows[:summary_count.min(1_000)].to_owned(),
  }
  let output : Map[String, Json] = {
    "contract": "moonleaf.table-explore.v1".to_json(),
    "sheets": names.to_json(),
    "sheet": sheet_name.to_json(),
    "columns": table.columns.to_json(),
    "rows": page.text_rows().to_json(),
    "row_indices": indexes[offset:end].to_owned().map(i => i + 2).to_json(),
    "source_rows": table.rows.length().to_json(),
    "matched_rows": indexes.length().to_json(),
    "offset": offset.to_json(),
    "limit": limit.to_json(),
    "truncated": (end < indexes.length()).to_json(),
    "summary": {
      "columns": summary.columns,
      "rows": summary_page.text_rows(),
      "total_rows": summary_count,
      "truncated": summary_count > 1_000,
    },
    "totals": totals,
    "formula_values": "cached_without_recalculation".to_json(),
  }
  if Json::object(output).stringify().length() > 2_097_152 {
    abort("table exploration report exceeds 2 MiB")
  }
  if args.length() == 6 {
    let format = explore_string(fields, "export_format", fallback="csv")
    let target = explore_string(fields, "export_target", fallback="rows")
    let export_table = match target {
      "rows" => selected
      "summary" => summary
      _ => abort("export_target must be rows or summary")
    }
    let bytes = match format {
      "csv" => {
        let text = "\u{FEFF}" + export_table.export_csv()
        let bytes = @utf8.encode(text).to_fixedarray()
        if bytes.length() > 2_097_152 {
          abort("table CSV export exceeds 2 MiB")
        }
        ignore(
          @csv.parse(text) catch {
            _ => abort("table CSV export verification failed")
          },
        )
        bytes
      }
      "xlsx" =>
        export_table.export_xlsx() catch {
          error => abort("MoonLeaf table XLSX export failed: \{Repr(error)}")
        }
      _ => abort("export_format must be csv or xlsx")
    }
    write_file(args[5], bytes)
    output["export"] = {
      "format": format,
      "target": target,
      "rows": export_table.rows.length(),
      "columns": export_table.columns.length(),
      "bytes": bytes.length(),
    }
  }
  let result = Json::object(output).stringify()
  if result.length() > 2_097_152 {
    abort("table exploration report exceeds 2 MiB")
  }
  println(result)
}
