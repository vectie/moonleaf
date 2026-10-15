///|
priv struct ExportSheet {
  name : String
  basename : String
  rows : Array[Array[@scene.CellValue]]
}

///|
priv suberror ExportError {
  Invalid(String)
}

///|
fn export_error(message : String) -> String {
  (
    {
      "contract": "moonleaf.browser-table-exports.v1",
      "version": "0.1.37",
      "files": [],
      "error": message,
    } : Json).stringify()
}

///|
fn export_basename(value : String) -> Bool {
  value.length() >= 1 &&
  value.length() <= 80 &&
  value.all(char => {
    (char >= 'a' && char <= 'z') ||
    (char >= 'A' && char <= 'Z') ||
    (char >= '0' && char <= '9') ||
    char == '_' ||
    char == '-'
  })
}

///|
fn collect_export_sheets(
  items : Array[Json],
) -> Array[ExportSheet] raise ExportError {
  guard items.length() >= 1 && items.length() <= 20 else {
    raise Invalid("Need 1..20 named sheets")
  }
  let sheets : Array[ExportSheet] = []
  let names : Array[String] = []
  let basenames : Array[String] = []
  let mut cell_count = 0
  let mut text_count = 0
  for item in items {
    guard item
      is {
        "name": String(name),
        "basename": String(basename),
        "rows": Array(rows),
        ..
      } &&
      export_basename(basename) &&
      !names.contains(name.to_lower()) &&
      !basenames.contains(basename.to_lower()) &&
      rows.length() <= 10000 else {
      raise Invalid(
        "Invalid or duplicate sheet name/basename, or oversized rows",
      )
    }
    names.push(name.to_lower())
    basenames.push(basename.to_lower())
    let cells : Array[Array[@scene.CellValue]] = []
    for row in rows {
      guard row is Array(values) && values.length() <= 256 else {
        raise Invalid("Invalid sheet row")
      }
      cell_count += values.length().max(1)
      guard cell_count <= 100000 else {
        raise Invalid("Tables exceed 100000 cells")
      }
      let values : Array[@scene.CellValue] = values.map(value => {
        match value {
          String(text) => {
            text_count += text.length()
            Text(text)
          }
          Number(number, ..) if !number.is_nan() && !number.is_inf() =>
            Number(number.to_string())
          Null => Empty
          True => Boolean(true)
          False => Boolean(false)
          _ =>
            raise Invalid(
              "Tables support text, finite numbers, booleans and nulls",
            )
        }
      })
      guard text_count <= 2000000 else {
        raise Invalid("Tables exceed 2 MB of cell text")
      }
      cells.push(values)
    }
    sheets.push({ name, basename, rows: cells, })
  }
  sheets
}

///|
fn encoded_file(
  name : String,
  mime : String,
  bytes : FixedArray[Byte],
) -> Json raise ExportError {
  guard bytes.length() <= 2097152 else {
    raise Invalid("Export file exceeds 2 MiB")
  }
  {
    "name": name,
    "mime": mime,
    "bytes": bytes.length(),
    "base64": @base64.encode(Bytes::from_array(bytes)),
    "writer": "moonleaf-moonbit",
  }
}

///|
fn export_tables(input : Json) -> Json raise {
  guard input is { "sheets": Array(items), .. } else {
    raise Invalid("Request needs sheets array")
  }
  let sheets = collect_export_sheets(items)
  let format = match input {
    { "format": String(format), .. } => format
    _ => "all"
  }
  guard ["all", "csv", "xlsx", "workbook"].contains(format) else {
    raise Invalid("Invalid export format")
  }
  let workbook = match input {
    { "workbook_name": String(name), .. } => name
    _ => ""
  }
  guard workbook == "" ||
    (
      workbook.has_suffix(".xlsx") &&
      export_basename(workbook[:workbook.length() - 5].to_owned())
    ) else {
    raise Invalid("workbook_name must be a simple .xlsx download filename")
  }
  guard format != "workbook" || workbook != "" else {
    raise Invalid("workbook format requires workbook_name")
  }
  let files : Array[Json] = []
  let mime = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
  for sheet in sheets {
    if format == "all" || format == "csv" {
      let bytes = match @csv.create(sheet.rows) {
        Ok(bytes) => bytes
        Err(message) => raise Invalid(message)
      }
      files.push(
        encoded_file(sheet.basename + ".csv", "text/csv;charset=utf-8", bytes),
      )
    }
    if format == "all" || format == "xlsx" {
      files.push(
        encoded_file(
          sheet.basename + ".xlsx",
          mime,
          @xlsx.create(sheet.rows, sheet_name=sheet.name),
        ),
      )
    }
  }
  if workbook != "" && format != "csv" {
    guard !files.any(file => {
      match file {
        { "name": String(name), .. } => name.to_lower() == workbook.to_lower()
        _ => false
      }
    }) else {
      raise Invalid("Workbook filename conflicts with sheet export")
    }
    files.push(
      encoded_file(
        workbook,
        mime,
        @xlsx.create_workbook(sheets.map(sheet => (sheet.name, sheet.rows))),
      ),
    )
  }
  {
    "contract": "moonleaf.browser-table-exports.v1",
    "version": "0.1.37",
    "files": files,
    "error": Json::null(),
  }
}

///|
/// Pure in-memory table export for browsers and other hosts. No filesystem,
/// network, Node APIs or native FFI are used by this library.
pub fn export_json(raw : String) -> String {
  if raw.length() > 2097152 {
    return export_error("Export request exceeds 2 MiB")
  }
  let input = @json.parse(raw) catch {
    _ => return export_error("Invalid export JSON")
  }
  try export_tables(input) catch {
    Invalid(message) => export_error(message)
    error =>
      export_error("MoonLeaf table export failed: " + Repr(error).to_string())
  } noraise {
    result => result.stringify()
  }
}
