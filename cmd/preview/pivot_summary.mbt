///|
fn pivot_table_rows(table : @jsontable.Table) -> Array[Array[@scene.CellValue]] {
  let rows = [table.columns.map(name => @scene.CellValue::Text(name))]
  for row in table.rows {
    rows.push(row.copy())
  }
  rows
}

///|
fn pivot_summary_copy(args : Array[String]) -> Unit {
  if args.length() != 6 {
    abort("usage: moonleaf-preview pivot-summary SOURCE DISPLAY_NAME OUTPUT")
  }
  let request = @json.parse(read_stdin()) catch {
    _ => abort("Pivot summary input must be JSON")
  }
  guard request is Object(fields) &&
    fields.get("sheet") is Some(String(sheet_name)) &&
    fields.get("row_columns") is Some(Array(dimensions)) &&
    fields.get("column_column") is Some(String(category)) &&
    fields.get("operation") is Some(String(aggregation)) else {
    abort(
      "Pivot summary requires sheet, row_columns, column_column and operation",
    )
  }
  let row_columns = dimensions.map(value => {
    guard value is String(name) else {
      abort("Pivot row columns must be header names")
    }
    name
  })
  let operation = match aggregation {
    "count" => @jsontable.CountRows
    "sum" | "mean" => {
      guard fields.get("value_column") is Some(String(name)) else {
        abort("Sum/mean pivot summary requires value_column")
      }
      if aggregation == "sum" {
        Sum(name)
      } else {
        Mean(name)
      }
    }
    _ => abort("Pivot operation must be sum, mean or count")
  }
  let filename = args[4].to_lower()
  let table = if filename.has_suffix(".xlsx") {
    let archive = @opc.open(read_file(args[3])) catch {
      error => abort("Pivot workbook open failed: " + repr(error))
    }
    let workbook = @xlsx.read(archive) catch {
      error => abort("Pivot workbook read failed: " + repr(error))
    }
    let selected = workbook.sheets
      .filter(sheet => sheet.name == sheet_name)
      .get(0)
    guard selected is Some(sheet) else {
      abort("Pivot worksheet was not found")
    }
    explore_sheet_table(sheet)
  } else if filename.has_suffix(".csv") || filename.has_suffix(".tsv") {
    @jsontable.parse_delimited(
      @utf8.decode(Bytes::from_array(read_file(args[3]))),
      delimiter=if filename.has_suffix(".tsv") { '\t' } else { ',' },
    ) catch {
      error => abort("Pivot delimited table read failed: " + repr(error))
    }
  } else {
    abort("Pivot summary supports XLSX, CSV and TSV")
  }
  let summary = table.pivot_summary(
    row_columns~,
    column_column=category,
    operation~,
  ) catch {
    error => abort("Pivot summary failed: " + repr(error))
  }
  let bytes = @xlsx.create_workbook([
    ("Source Data", pivot_table_rows(table)),
    ("Pivot Summary", pivot_table_rows(summary)),
  ]) catch {
    error => abort("Pivot workbook creation failed: " + repr(error))
  }
  write_file(args[5], bytes)
  let receipt : Json = {
    "contract": "moonleaf.pivot-summary-copy.v1",
    "bytes": bytes.length(),
    "source_rows": table.rows.length(),
    "summary_rows": summary.rows.length(),
    "summary_columns": summary.columns.length(),
    "columns": summary.columns,
    "sheet": "Pivot Summary",
    "operation": aggregation,
  }
  println(receipt.stringify())
}
