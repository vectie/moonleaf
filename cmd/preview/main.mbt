///|
/// Keep an edited delimited copy within MoonLeaf's parser limits and make sure
/// every row survives a save/open cycle before the caller can publish it.
fn verified_delimited_bytes(
  table : @csv.Table,
  original : String,
) -> FixedArray[Byte] {
  let serialized = (if original.has_prefix("\u{FEFF}") {
      "\u{FEFF}"
    } else {
      ""
    }) +
    table.serialize()
  let bytes = @utf8.encode(serialized).to_fixedarray()
  if bytes.length() > 8_388_608 {
    abort("edited delimited file exceeds 8 MiB")
  }
  let reopened = @csv.parse(serialized, delimiter=table.delimiter) catch {
    _ => abort("MoonLeaf edited copy failed verification")
  }
  if reopened.rows != table.rows {
    abort("MoonLeaf edited copy failed verification")
  }
  bytes
}

///|
fn cell_text(value : @scene.CellValue) -> String {
  match value {
    Empty => ""
    Text(text) | Number(text) | Error(text) => text
    Boolean(value) => if value { "TRUE" } else { "FALSE" }
    Formula(expression~, cached~) => cached.unwrap_or("=" + expression)
  }
}

///|
/// Only a finite numeric XLSX cell may receive a number-format display.
/// Formula caches are classified separately from their original XML result
/// type, so text/boolean caches are not accidentally treated as numbers.
fn is_numeric_cell(value : @scene.CellValue) -> Bool {
  match value {
    Number(text) => {
      let parsed = @string.parse_double(text[:]) catch { _ => return false }
      !parsed.is_nan() && !parsed.is_inf()
    }
    _ => false
  }
}

///|
fn sheet_json(
  sheet : @scene.Sheet,
  total : Ref[Int],
  text_size : Ref[Int],
  wrapped : Array[(Int, Int)],
  bold : Array[(Int, Int)],
  italic : Array[(Int, Int)],
  underlined : Array[(Int, Int)],
  horizontal : Array[(Int, Int, String)],
  number_formats : Array[(Int, Int, String)],
  decimal_places : Array[(Int, Int, Int)],
  hidden_rows : Array[Int],
  numeric_formulas? : Array[(Int, Int)] = [],
) -> Json {
  let rows : Array[Array[String]] = []
  let numeric_cells : Array[Json] = []
  let formula_cells : Array[Json] = []
  let formula_expressions : Array[Json] = []
  for cell in sheet.cells {
    if cell.row < 1 || cell.row > 10_000 || cell.column < 1 || cell.column > 256 {
      abort("spreadsheet preview exceeds row or column limit")
    }
    while rows.length() < cell.row {
      rows.push([])
    }
    let row = rows[cell.row - 1]
    while row.length() < cell.column {
      row.push("")
      total.val += 1
      if total.val > 100_000 {
        abort("spreadsheet preview exceeds cell limit")
      }
    }
    let value = cell_text(cell.value)
    if is_numeric_cell(cell.value) ||
      (
        cell.value is Formula(..) &&
        numeric_formulas.contains((cell.row, cell.column))
      ) {
      let coordinate : Json = [cell.row, cell.column]
      numeric_cells.push(coordinate)
    }
    if cell.value is Formula(expression~, ..) {
      let coordinate : Json = [cell.row, cell.column]
      formula_cells.push(coordinate)
      formula_expressions.push(
        [cell.row.to_json(), cell.column.to_json(), expression.to_json()].to_json(),
      )
    }
    text_size.val += value.length()
    if text_size.val > 8_388_608 {
      abort("spreadsheet preview exceeds text limit")
    }
    row[cell.column - 1] = value
  }
  let wrapped_cells : Array[Json] = wrapped.map(coordinate => {
    let value : Json = [coordinate.0, coordinate.1]
    value
  })
  let bold_cells : Array[Json] = bold.map(coordinate => {
    let value : Json = [coordinate.0, coordinate.1]
    value
  })
  let italic_cells : Array[Json] = italic.map(coordinate => {
    let value : Json = [coordinate.0, coordinate.1]
    value
  })
  let underlined_cells : Array[Json] = underlined.map(coordinate => {
    let value : Json = [coordinate.0, coordinate.1]
    value
  })
  let horizontal_alignment_cells : Array[Json] = horizontal.map(coordinate => {
    let value : Json = [coordinate.0, coordinate.1, coordinate.2]
    value
  })
  let number_format_cells : Array[Json] = number_formats.map(coordinate => {
    let value : Json = [coordinate.0, coordinate.1, coordinate.2]
    value
  })
  let decimal_places_cells : Array[Json] = decimal_places.map(coordinate => {
    let value : Json = [coordinate.0, coordinate.1, coordinate.2]
    value
  })
  {
    "name": sheet.name,
    "rows": rows,
    "numeric_cells": numeric_cells,
    "formula_cells": formula_cells,
    "formula_expressions": formula_expressions,
    "wrapped_cells": wrapped_cells,
    "bold_cells": bold_cells,
    "italic_cells": italic_cells,
    "underlined_cells": underlined_cells,
    "horizontal_alignment_cells": horizontal_alignment_cells,
    "number_format_cells": number_format_cells,
    "decimal_places_cells": decimal_places_cells,
    "hidden_rows": hidden_rows,
  }
}

///|
fn preview(source : String, filename : String) -> Unit {
  let bytes = read_file(source)
  let scene = @moonleaf.open(filename, bytes) catch {
    error => {
      report_error("MoonLeaf open failed: \{Repr(error)}")
      abort("MoonLeaf open failed")
    }
  }
  guard scene is WorkbookDocument(workbook) else {
    abort("MoonLeaf did not return a workbook")
  }
  if workbook.sheets.length() > 20 {
    abort("spreadsheet preview exceeds sheet limit")
  }
  let total = Ref(0)
  let text_size = Ref(0)
  let xlsx_package = if filename.to_lower().has_suffix(".xlsx") {
    Some(
      @opc.open(bytes) catch {
        _ => abort("MoonLeaf XLSX preview failed archive verification")
      },
    )
  } else {
    None
  }
  let sheets = workbook.sheets.map(sheet => {
    let wrapped = match xlsx_package {
      Some(archive) =>
        @xlsx.wrapped_cells(archive, sheet.name) catch {
          error => abort("MoonLeaf XLSX wrap inspection failed: \{Repr(error)}")
        }
      None => []
    }
    let bold = match xlsx_package {
      Some(archive) =>
        @xlsx.font_decoration_cells(archive, sheet.name, Bold) catch {
          error => abort("MoonLeaf XLSX font inspection failed: \{Repr(error)}")
        }
      None => []
    }
    let italic = match xlsx_package {
      Some(archive) =>
        @xlsx.font_decoration_cells(archive, sheet.name, Italic) catch {
          error => abort("MoonLeaf XLSX font inspection failed: \{Repr(error)}")
        }
      None => []
    }
    let underlined = match xlsx_package {
      Some(archive) =>
        @xlsx.font_decoration_cells(archive, sheet.name, Underline) catch {
          error => abort("MoonLeaf XLSX font inspection failed: \{Repr(error)}")
        }
      None => []
    }
    let horizontal = match xlsx_package {
      Some(archive) =>
        @xlsx.horizontal_alignment_cells(archive, sheet.name) catch {
          error =>
            abort("MoonLeaf XLSX alignment inspection failed: \{Repr(error)}")
        }
      None => []
    }
    let number_formats = match xlsx_package {
      Some(archive) =>
        @xlsx.number_format_cells(archive, sheet.name) catch {
          error =>
            abort(
              "MoonLeaf XLSX number format inspection failed: \{Repr(error)}",
            )
        }
      None => []
    }
    let decimal_places = match xlsx_package {
      Some(archive) =>
        @xlsx.number_format_places_cells(archive, sheet.name) catch {
          error =>
            abort(
              "MoonLeaf XLSX decimal precision inspection failed: \{Repr(error)}",
            )
        }
      None => []
    }
    let hidden_rows = match xlsx_package {
      Some(archive) =>
        @xlsx.hidden_sheet_rows(archive, sheet.name) catch {
          error =>
            abort(
              "MoonLeaf XLSX row visibility inspection failed: \{Repr(error)}",
            )
        }
      None => []
    }
    let numeric_formulas = match xlsx_package {
      Some(archive) =>
        @xlsx.numeric_formula_cells(archive, sheet.name) catch {
          error =>
            abort(
              "MoonLeaf XLSX formula cache inspection failed: \{Repr(error)}",
            )
        }
      None => []
    }
    sheet_json(
      sheet,
      total,
      text_size,
      wrapped,
      bold,
      italic,
      underlined,
      horizontal,
      number_formats,
      decimal_places,
      hidden_rows,
      numeric_formulas~,
    )
  })
  let preview : Json = { "sheets": sheets }
  println(preview.stringify())
}

///|
fn edit(args : Array[String]) -> Unit {
  if args.length() != 9 {
    abort("usage: moonleaf-preview edit SOURCE NAME SHEET ROW COLUMN OUTPUT")
  }
  let source = args[3]
  let filename = args[4]
  let sheet = args[5]
  let row = @string.parse_int(args[6][:]) catch { _ => abort("invalid row") }
  let column = @string.parse_int(args[7][:]) catch {
    _ => abort("invalid column")
  }
  let output = args[8]
  let value = read_stdin()
  if value.length() > 32_768 {
    abort("cell text exceeds limit")
  }
  let bytes = read_file(source)
  if filename.to_lower().has_suffix(".xlsx") {
    let session = @moonleaf.open_session(filename, bytes) catch {
      error => {
        report_error("MoonLeaf open failed: \{Repr(error)}")
        abort("MoonLeaf open failed")
      }
    }
    let edited = session.set_cell_text(sheet, row, column, value) catch {
      error => {
        report_error("MoonLeaf cell edit failed: \{Repr(error)}")
        abort("MoonLeaf cell edit failed")
      }
    }
    let copy = edited.save_as_copy() catch {
      error => {
        report_error("MoonLeaf save failed: \{Repr(error)}")
        abort("MoonLeaf save failed")
      }
    }
    write_file(output, copy.bytes())
  } else if filename.to_lower().has_suffix(".csv") ||
    filename.to_lower().has_suffix(".tsv") {
    if sheet != "工作表1" {
      abort("unknown CSV sheet")
    }
    let text = @utf8.decode(Bytes::from_array(bytes)) catch {
      _ => abort("invalid UTF-8")
    }
    let delimiter = if filename.to_lower().has_suffix(".tsv") {
      '\t'
    } else {
      ','
    }
    let table = @csv.parse(text, delimiter~) catch {
      _ => {
        report_error("MoonLeaf CSV open failed")
        abort("MoonLeaf CSV open failed")
      }
    }
    let edited = table.set_cell_text(row, column, safe_csv_text(value)) catch {
      _ => {
        report_error("MoonLeaf CSV cell edit failed")
        abort("MoonLeaf CSV cell edit failed")
      }
    }
    write_file(output, verified_delimited_bytes(edited, text))
  } else {
    abort("unsupported spreadsheet format")
  }
}

///|
/// Turn a bounded clipboard rectangle into 1-based cell edits. Empty strings
/// clear cells; ragged rows leave the omitted trailing cells untouched.
fn paste_edits(request : Json) -> (String, Array[(Int, Int, String)]) {
  guard request
    is {
      "sheet": String(sheet),
      "start_row": Number(row_number, ..),
      "start_column": Number(column_number, ..),
      "rows": Array(rows),
      ..
    } else {
    abort("paste request needs sheet, start_row, start_column and rows")
  }
  let start_row = @string.parse_int(row_number.to_string()[:]) catch {
    _ => abort("paste start_row must be an integer")
  }
  let start_column = @string.parse_int(column_number.to_string()[:]) catch {
    _ => abort("paste start_column must be an integer")
  }
  if sheet.is_empty() ||
    start_row < 1 ||
    start_row > 10_000 ||
    start_column < 1 ||
    start_column > 256 ||
    rows.is_empty() ||
    rows.length() > 1_000 {
    abort("paste range exceeds bounds")
  }
  let edits : Array[(Int, Int, String)] = []
  for row_offset, item in rows {
    guard item is Array(values) && !values.is_empty() else {
      abort("paste rows must contain text cells")
    }
    if start_row + row_offset > 10_000 ||
      start_column + values.length() - 1 > 256 {
      abort("paste range exceeds bounds")
    }
    for column_offset, value in values {
      guard value is String(text) else { abort("paste cells must be strings") }
      if text.length() > 32_768 {
        abort("paste cell text exceeds limit")
      }
      edits.push((start_row + row_offset, start_column + column_offset, text))
      if edits.length() > 1_000 {
        abort("paste exceeds 1000 cells")
      }
    }
  }
  (sheet, edits)
}

///|
/// Write a verified copy after one atomic paste. XLSX edits target existing
/// non-formula cells; CSV/TSV may extend the table within parser limits.
fn paste_range(args : Array[String]) -> Unit {
  if args.length() != 6 {
    abort("usage: moonleaf-preview paste-range SOURCE NAME OUTPUT")
  }
  let raw = read_stdin()
  if raw.length() > 2_097_152 {
    abort("paste request exceeds 2 MiB")
  }
  let request = @json.parse(raw) catch { _ => abort("invalid paste request") }
  let (sheet, edits) = paste_edits(request)
  let source = args[3]
  let filename = args[4]
  let output = args[5]
  let bytes = read_file(source)
  if filename.to_lower().has_suffix(".xlsx") {
    let session = @moonleaf.open_session(filename, bytes) catch {
      error => abort("MoonLeaf open failed: \{Repr(error)}")
    }
    let edited = session.set_cells_text(sheet, edits) catch {
      error => abort("MoonLeaf paste failed: \{Repr(error)}")
    }
    let copy = edited.save_as_copy() catch {
      error => abort("MoonLeaf save failed: \{Repr(error)}")
    }
    write_file(output, copy.bytes())
  } else if filename.to_lower().has_suffix(".csv") ||
    filename.to_lower().has_suffix(".tsv") {
    if sheet != "工作表1" {
      abort("unknown CSV sheet")
    }
    let text = @utf8.decode(Bytes::from_array(bytes)) catch {
      _ => abort("invalid UTF-8")
    }
    let delimiter = if filename.to_lower().has_suffix(".tsv") {
      '\t'
    } else {
      ','
    }
    let table = @csv.parse(text, delimiter~) catch {
      _ => abort("MoonLeaf delimited open failed")
    }
    let safe_edits = edits.map(fn(edit) {
      let (row, column, value) = edit
      (row, column, safe_csv_text(value))
    })
    let edited = table.set_cells_text(safe_edits) catch {
      _ => abort("MoonLeaf paste failed")
    }
    write_file(output, verified_delimited_bytes(edited, text))
  } else {
    abort("unsupported spreadsheet format")
  }
  let result : Json = {
    "contract": "moonleaf.paste-range.v1",
    "pasted_cells": edits.length(),
  }
  println(result.stringify())
}

///|
/// Clear visible content in a bounded rectangle and write a verified copy.
/// This differs from pasting empty strings: formulas may be cleared and XLSX
/// cell styles survive, while missing cells are never created.
fn clear_range(args : Array[String]) -> Unit {
  if args.length() != 6 {
    abort("usage: moonleaf-preview clear-range SOURCE NAME OUTPUT")
  }
  let raw = read_stdin()
  if raw.length() > 16_384 {
    abort("clear request exceeds limit")
  }
  let request = @json.parse(raw) catch { _ => abort("invalid clear request") }
  guard request
    is {
      "sheet": String(sheet),
      "start_row": Number(start_row_number, ..),
      "start_column": Number(start_column_number, ..),
      "end_row": Number(end_row_number, ..),
      "end_column": Number(end_column_number, ..),
      ..
    } else {
    abort("clear request needs sheet and range coordinates")
  }
  let start_row = @string.parse_int(start_row_number.to_string()[:]) catch {
    _ => abort("clear start_row must be an integer")
  }
  let start_column = @string.parse_int(start_column_number.to_string()[:]) catch {
    _ => abort("clear start_column must be an integer")
  }
  let end_row = @string.parse_int(end_row_number.to_string()[:]) catch {
    _ => abort("clear end_row must be an integer")
  }
  let end_column = @string.parse_int(end_column_number.to_string()[:]) catch {
    _ => abort("clear end_column must be an integer")
  }
  if sheet.is_empty() ||
    start_row < 1 ||
    start_column < 1 ||
    end_row < start_row ||
    end_column < start_column ||
    end_row > 10_000 ||
    end_column > 256 ||
    (end_row - start_row + 1) * (end_column - start_column + 1) > 1_000 {
    abort("clear range exceeds bounds")
  }
  let source = args[3]
  let filename = args[4]
  let output = args[5]
  let bytes = read_file(source)
  let mut count = 0
  if filename.to_lower().has_suffix(".xlsx") {
    let archive = @opc.open(bytes) catch {
      error => abort("MoonLeaf XLSX open failed: \{Repr(error)}")
    }
    let (cleared, cleared_cells) = @xlsx.clear_sheet_range(
      archive, sheet, start_row, start_column, end_row, end_column,
    ) catch {
      error => abort("MoonLeaf XLSX clear failed: \{Repr(error)}")
    }
    count = cleared_cells
    if count > 0 {
      let copy = @opc.save(cleared) catch {
        error => abort("MoonLeaf XLSX save failed: \{Repr(error)}")
      }
      let reopened = @opc.open(copy) catch {
        _ => abort("MoonLeaf cleared copy failed archive verification")
      }
      ignore(
        @xlsx.read(reopened) catch {
          _ => abort("MoonLeaf cleared copy failed workbook verification")
        },
      )
      write_file(output, copy)
    }
  } else if filename.to_lower().has_suffix(".csv") ||
    filename.to_lower().has_suffix(".tsv") {
    if sheet != "工作表1" {
      abort("unknown CSV sheet")
    }
    let text = @utf8.decode(Bytes::from_array(bytes)) catch {
      _ => abort("invalid UTF-8")
    }
    let delimiter = if filename.to_lower().has_suffix(".tsv") {
      '\t'
    } else {
      ','
    }
    let table = @csv.parse(text, delimiter~) catch {
      _ => abort("MoonLeaf delimited open failed")
    }
    let rows = table.rows.map(row => row.copy())
    for row in start_row..<=end_row {
      if row <= rows.length() {
        let values = rows[row - 1]
        for column in start_column..<=end_column {
          if column <= values.length() && values[column - 1] != "" {
            values[column - 1] = ""
            count += 1
          }
        }
      }
    }
    if count > 0 {
      let cleared : @csv.Table = { rows, delimiter, }
      write_file(output, verified_delimited_bytes(cleared, text))
    }
  } else {
    abort("unsupported spreadsheet format")
  }
  let result : Json = {
    "contract": "moonleaf.clear-range.v1",
    "cleared_cells": count,
  }
  println(result.stringify())
}

///|
/// Toggle automatic wrapping on existing XLSX cells and save a verified copy.
fn format_wrap(args : Array[String]) -> Unit {
  if args.length() != 6 {
    abort("usage: moonleaf-preview format-wrap SOURCE NAME OUTPUT")
  }
  if !args[4].to_lower().has_suffix(".xlsx") {
    abort("automatic wrapping requires XLSX")
  }
  let raw = read_stdin()
  if raw.length() > 16_384 {
    abort("wrap request exceeds limit")
  }
  let request = @json.parse(raw) catch { _ => abort("invalid wrap request") }
  guard request
    is {
      "sheet": String(sheet),
      "start_row": Number(start_row_number, ..),
      "start_column": Number(start_column_number, ..),
      "end_row": Number(end_row_number, ..),
      "end_column": Number(end_column_number, ..),
      "enabled": enabled_value,
      ..
    } else {
    abort("wrap request needs sheet, range and enabled flag")
  }
  let start_row = @string.parse_int(start_row_number.to_string()[:]) catch {
    _ => abort("wrap start_row must be an integer")
  }
  let start_column = @string.parse_int(start_column_number.to_string()[:]) catch {
    _ => abort("wrap start_column must be an integer")
  }
  let end_row = @string.parse_int(end_row_number.to_string()[:]) catch {
    _ => abort("wrap end_row must be an integer")
  }
  let end_column = @string.parse_int(end_column_number.to_string()[:]) catch {
    _ => abort("wrap end_column must be an integer")
  }
  let enabled = match enabled_value {
    True => true
    False => false
    _ => abort("wrap enabled must be Boolean")
  }
  if sheet.is_empty() ||
    start_row < 1 ||
    start_column < 1 ||
    end_row < start_row ||
    end_column < start_column ||
    end_row > 10_000 ||
    end_column > 256 ||
    (end_row - start_row + 1) * (end_column - start_column + 1) > 1_000 {
    abort("wrap range exceeds bounds")
  }
  let archive = @opc.open(read_file(args[3])) catch {
    error => abort("MoonLeaf XLSX open failed: \{Repr(error)}")
  }
  let (formatted, count) = @xlsx.set_wrap_text_range(
    archive, sheet, start_row, start_column, end_row, end_column, enabled,
  ) catch {
    error => abort("MoonLeaf XLSX wrap failed: \{Repr(error)}")
  }
  if count > 0 {
    let copy = @opc.save(formatted) catch {
      error => abort("MoonLeaf XLSX save failed: \{Repr(error)}")
    }
    let reopened = @opc.open(copy) catch {
      _ => abort("MoonLeaf wrapped copy failed archive verification")
    }
    ignore(
      @xlsx.read(reopened) catch {
        _ => abort("MoonLeaf wrapped copy failed workbook verification")
      },
    )
    ignore(
      @xlsx.wrapped_cells(reopened, sheet) catch {
        _ => abort("MoonLeaf wrapped copy failed style verification")
      },
    )
    write_file(args[5], copy)
  }
  let receipt : Json = {
    "contract": "moonleaf.format-wrap.v1",
    "formatted_cells": count,
    "enabled": enabled,
  }
  println(receipt.stringify())
}

///|
/// Toggle bold, italic or underline on a selected XLSX range and save a verified copy.
fn format_font(args : Array[String]) -> Unit {
  if args.length() != 6 {
    abort("usage: moonleaf-preview format-font SOURCE NAME OUTPUT")
  }
  if !args[4].to_lower().has_suffix(".xlsx") {
    abort("font decoration requires XLSX")
  }
  let raw = read_stdin()
  if raw.length() > 16_384 {
    abort("font request exceeds limit")
  }
  let request = @json.parse(raw) catch { _ => abort("invalid font request") }
  guard request
    is {
      "sheet": String(sheet),
      "start_row": Number(start_row_number, ..),
      "start_column": Number(start_column_number, ..),
      "end_row": Number(end_row_number, ..),
      "end_column": Number(end_column_number, ..),
      "decoration": String(decoration_name),
      "enabled": enabled_value,
      ..
    } else {
    abort("font request needs sheet, range, decoration and enabled flag")
  }
  let start_row = @string.parse_int(start_row_number.to_string()[:]) catch {
    _ => abort("font start_row must be an integer")
  }
  let start_column = @string.parse_int(start_column_number.to_string()[:]) catch {
    _ => abort("font start_column must be an integer")
  }
  let end_row = @string.parse_int(end_row_number.to_string()[:]) catch {
    _ => abort("font end_row must be an integer")
  }
  let end_column = @string.parse_int(end_column_number.to_string()[:]) catch {
    _ => abort("font end_column must be an integer")
  }
  let decoration = match decoration_name {
    "bold" => @xlsx.Bold
    "italic" => Italic
    "underline" => Underline
    _ => abort("font decoration must be bold, italic or underline")
  }
  let enabled = match enabled_value {
    True => true
    False => false
    _ => abort("font enabled must be Boolean")
  }
  if sheet.is_empty() ||
    start_row < 1 ||
    start_column < 1 ||
    end_row < start_row ||
    end_column < start_column ||
    end_row > 10_000 ||
    end_column > 256 ||
    (end_row - start_row + 1) * (end_column - start_column + 1) > 1_000 {
    abort("font range exceeds bounds")
  }
  let archive = @opc.open(read_file(args[3])) catch {
    error => abort("MoonLeaf XLSX open failed: \{Repr(error)}")
  }
  let (formatted, count) = @xlsx.set_font_decoration_range(
    archive, sheet, start_row, start_column, end_row, end_column, decoration, enabled,
  ) catch {
    error => abort("MoonLeaf XLSX font format failed: \{Repr(error)}")
  }
  if count > 0 {
    let copy = @opc.save(formatted) catch {
      error => abort("MoonLeaf XLSX save failed: \{Repr(error)}")
    }
    let reopened = @opc.open(copy) catch {
      _ => abort("MoonLeaf formatted copy failed archive verification")
    }
    ignore(@xlsx.read(reopened)) catch {
      _ => abort("MoonLeaf formatted copy failed workbook verification")
    }
    ignore(@xlsx.font_decoration_cells(reopened, sheet, decoration)) catch {
      _ => abort("MoonLeaf formatted copy failed style verification")
    }
    write_file(args[5], copy)
  }
  let receipt : Json = {
    "contract": "moonleaf.format-font.v1",
    "formatted_cells": count,
    "decoration": decoration_name,
    "enabled": enabled,
  }
  println(receipt.stringify())
}

///|
/// Save a copy with left, center or right XLSX horizontal alignment.
fn format_align(args : Array[String]) -> Unit {
  if args.length() != 6 {
    abort("usage: moonleaf-preview format-align SOURCE NAME OUTPUT")
  }
  if !args[4].to_lower().has_suffix(".xlsx") {
    abort("horizontal alignment requires XLSX")
  }
  let raw = read_stdin()
  if raw.length() > 16_384 {
    abort("alignment request exceeds limit")
  }
  let request = @json.parse(raw) catch {
    _ => abort("invalid alignment request")
  }
  guard request
    is {
      "sheet": String(sheet),
      "start_row": Number(start_row_number, ..),
      "start_column": Number(start_column_number, ..),
      "end_row": Number(end_row_number, ..),
      "end_column": Number(end_column_number, ..),
      "alignment": String(alignment_name),
      ..
    } else {
    abort("alignment request needs sheet, range and alignment")
  }
  let start_row = @string.parse_int(start_row_number.to_string()[:]) catch {
    _ => abort("alignment start_row must be an integer")
  }
  let start_column = @string.parse_int(start_column_number.to_string()[:]) catch {
    _ => abort("alignment start_column must be an integer")
  }
  let end_row = @string.parse_int(end_row_number.to_string()[:]) catch {
    _ => abort("alignment end_row must be an integer")
  }
  let end_column = @string.parse_int(end_column_number.to_string()[:]) catch {
    _ => abort("alignment end_column must be an integer")
  }
  let alignment = match alignment_name {
    "left" => @xlsx.Left
    "center" => Center
    "right" => Right
    _ => abort("alignment must be left, center or right")
  }
  if sheet.is_empty() ||
    start_row < 1 ||
    start_column < 1 ||
    end_row < start_row ||
    end_column < start_column ||
    end_row > 10_000 ||
    end_column > 256 ||
    (end_row - start_row + 1) * (end_column - start_column + 1) > 1_000 {
    abort("alignment range exceeds bounds")
  }
  let archive = @opc.open(read_file(args[3])) catch {
    error => abort("MoonLeaf XLSX open failed: \{Repr(error)}")
  }
  let (formatted, count) = @xlsx.set_horizontal_alignment_range(
    archive, sheet, start_row, start_column, end_row, end_column, alignment,
  ) catch {
    error => abort("MoonLeaf XLSX alignment failed: \{Repr(error)}")
  }
  if count > 0 {
    let copy = @opc.save(formatted) catch {
      error => abort("MoonLeaf XLSX save failed: \{Repr(error)}")
    }
    let reopened = @opc.open(copy) catch {
      _ => abort("MoonLeaf aligned copy failed archive verification")
    }
    ignore(@xlsx.read(reopened)) catch {
      _ => abort("MoonLeaf aligned copy failed workbook verification")
    }
    ignore(@xlsx.horizontal_alignment_cells(reopened, sheet)) catch {
      _ => abort("MoonLeaf aligned copy failed style verification")
    }
    write_file(args[5], copy)
  }
  let receipt : Json = {
    "contract": "moonleaf.format-align.v1",
    "formatted_cells": count,
    "alignment": alignment_name,
  }
  println(receipt.stringify())
}

///|
/// Save a copy with a common XLSX number format on a selected range.
fn format_number(args : Array[String]) -> Unit {
  if args.length() != 6 {
    abort("usage: moonleaf-preview format-number SOURCE NAME OUTPUT")
  }
  if !args[4].to_lower().has_suffix(".xlsx") {
    abort("number formatting requires XLSX")
  }
  let raw = read_stdin()
  if raw.length() > 16_384 {
    abort("number format request exceeds limit")
  }
  let request = @json.parse(raw) catch {
    _ => abort("invalid number format request")
  }
  guard request
    is {
      "sheet": String(sheet),
      "start_row": Number(start_row_number, ..),
      "start_column": Number(start_column_number, ..),
      "end_row": Number(end_row_number, ..),
      "end_column": Number(end_column_number, ..),
      "format": String(format_name),
      ..
    } else {
    abort("number format request needs sheet, range and format")
  }
  let start_row = @string.parse_int(start_row_number.to_string()[:]) catch {
    _ => abort("number format start_row must be an integer")
  }
  let start_column = @string.parse_int(start_column_number.to_string()[:]) catch {
    _ => abort("number format start_column must be an integer")
  }
  let end_row = @string.parse_int(end_row_number.to_string()[:]) catch {
    _ => abort("number format end_row must be an integer")
  }
  let end_column = @string.parse_int(end_column_number.to_string()[:]) catch {
    _ => abort("number format end_column must be an integer")
  }
  let preset = match format_name {
    "general" => @xlsx.FormatGeneral
    "number" => FormatNumber
    "percent" => FormatPercent
    "currency" => FormatCurrency
    _ => abort("number format must be general, number, percent or currency")
  }
  let decimal_places : Int? = match request {
    { "decimal_places": Number(value, ..), .. } =>
      Some(
        @string.parse_int(value.to_string()[:]) catch {
          _ => abort("decimal_places must be an integer")
        },
      )
    { "decimal_places": _, .. } => abort("decimal_places must be an integer")
    _ => None
  }
  if sheet.is_empty() ||
    start_row < 1 ||
    start_column < 1 ||
    end_row < start_row ||
    end_column < start_column ||
    end_row > 10_000 ||
    end_column > 256 ||
    (end_row - start_row + 1) * (end_column - start_column + 1) > 1_000 {
    abort("number format range exceeds bounds")
  }
  let archive = @opc.open(read_file(args[3])) catch {
    error => abort("MoonLeaf XLSX open failed: \{Repr(error)}")
  }
  let (formatted, count) = try {
    match decimal_places {
      Some(places) =>
        @xlsx.set_number_format_places_range(
          archive, sheet, start_row, start_column, end_row, end_column, preset, places,
        )
      None =>
        @xlsx.set_number_format_range(
          archive, sheet, start_row, start_column, end_row, end_column, preset,
        )
    }
  } catch {
    error => abort("MoonLeaf XLSX number format failed: \{Repr(error)}")
  }
  if count > 0 {
    let copy = @opc.save(formatted) catch {
      error => abort("MoonLeaf XLSX save failed: \{Repr(error)}")
    }
    let reopened = @opc.open(copy) catch {
      _ => abort("MoonLeaf number formatted copy failed archive verification")
    }
    ignore(@xlsx.read(reopened)) catch {
      _ => abort("MoonLeaf number formatted copy failed workbook verification")
    }
    ignore(@xlsx.number_format_cells(reopened, sheet)) catch {
      _ => abort("MoonLeaf number formatted copy failed style verification")
    }
    write_file(args[5], copy)
  }
  let receipt : Json = match decimal_places {
    Some(places) =>
      {
        "contract": "moonleaf.format-number.v1",
        "formatted_cells": count,
        "format": format_name,
        "decimal_places": places,
      }
    None =>
      {
        "contract": "moonleaf.format-number.v1",
        "formatted_cells": count,
        "format": format_name,
      }
  }
  println(receipt.stringify())
}

///|
/// Save a verified XLSX copy after inserting or deleting whole worksheet rows.
/// The source path is read only, so the caller can undo by reopening it.
fn edit_rows(args : Array[String], insert : Bool) -> Unit {
  let operation = if insert { "insert-rows" } else { "delete-rows" }
  if args.length() != 6 {
    abort("usage: moonleaf-preview \{operation} SOURCE NAME OUTPUT")
  }
  let filename = args[4].to_lower()
  let is_xlsx = filename.has_suffix(".xlsx")
  let is_csv = filename.has_suffix(".csv")
  let is_tsv = filename.has_suffix(".tsv")
  if !is_xlsx && !is_csv && !is_tsv {
    abort("row editing requires XLSX, CSV or TSV")
  }
  let raw = read_stdin()
  if raw.length() > 16_384 {
    abort("row edit request exceeds limit")
  }
  let request = @json.parse(raw) catch {
    _ => abort("invalid row edit request")
  }
  guard request
    is {
      "sheet": String(sheet),
      "row": Number(row_number, ..),
      "count": Number(count_number, ..),
      ..
    } else {
    abort("row edit request needs sheet, row and count")
  }
  let row = @string.parse_int(row_number.to_string()[:]) catch {
    _ => abort("row must be an integer")
  }
  let count = @string.parse_int(count_number.to_string()[:]) catch {
    _ => abort("count must be an integer")
  }
  if sheet.is_empty() ||
    row < 1 ||
    row > 10_000 ||
    count < 1 ||
    count > 100 ||
    count > 10_000 - row + 1 {
    abort("row edit exceeds preview bounds")
  }
  let changed = if is_xlsx {
    let archive = @opc.open(read_file(args[3])) catch {
      error => abort("MoonLeaf XLSX open failed: \{Repr(error)}")
    }
    let (edited, changed) = try {
      if insert {
        @xlsx.insert_sheet_rows(archive, sheet, row, count)
      } else {
        @xlsx.delete_sheet_rows(archive, sheet, row, count)
      }
    } catch {
      error => abort("MoonLeaf XLSX row edit failed: \{Repr(error)}")
    }
    if changed > 0 {
      let copy = @opc.save(edited) catch {
        error => abort("MoonLeaf XLSX save failed: \{Repr(error)}")
      }
      let reopened = @opc.open(copy) catch {
        _ => abort("MoonLeaf row edited copy failed archive verification")
      }
      ignore(@xlsx.read(reopened)) catch {
        _ => abort("MoonLeaf row edited copy failed workbook verification")
      }
      write_file(args[5], copy)
    }
    changed
  } else {
    if sheet != "工作表1" {
      abort("unknown CSV sheet")
    }
    let source = @utf8.decode(Bytes::from_array(read_file(args[3]))) catch {
      _ => abort("invalid UTF-8")
    }
    let delimiter = if is_tsv { '\t' } else { ',' }
    let table = @csv.parse(source, delimiter~) catch {
      _ => abort("MoonLeaf delimited parse failed")
    }
    let (edited, changed) = try {
      if insert {
        (table.insert_rows(row, count), count)
      } else {
        table.delete_rows(row, count)
      }
    } catch {
      _ => abort("MoonLeaf delimited row edit failed")
    }
    if changed > 0 {
      write_file(args[5], verified_delimited_bytes(edited, source))
    }
    changed
  }
  let receipt : Json = {
    "contract": if insert {
      "moonleaf.insert-rows.v1"
    } else {
      "moonleaf.delete-rows.v1"
    },
    "sheet": sheet,
    "row": row,
    "requested_rows": count,
    "changed_rows": changed,
    "saved_copy": changed > 0,
    "source_unchanged": true,
  }
  println(receipt.stringify())
}

///|
/// Edit whole XLSX, CSV or TSV columns into a separate, verified copy.
/// XLSX edits reject formula and anchored-object references they cannot update.
fn edit_columns(args : Array[String], insert : Bool) -> Unit {
  let operation = if insert { "insert-columns" } else { "delete-columns" }
  if args.length() != 6 {
    abort("usage: moonleaf-preview \{operation} SOURCE NAME OUTPUT")
  }
  let filename = args[4].to_lower()
  let is_xlsx = filename.has_suffix(".xlsx")
  let is_csv = filename.has_suffix(".csv")
  let is_tsv = filename.has_suffix(".tsv")
  if !is_xlsx && !is_csv && !is_tsv {
    abort("column editing requires XLSX, CSV or TSV")
  }
  let raw = read_stdin()
  if raw.length() > 16_384 {
    abort("column edit request exceeds limit")
  }
  let request = @json.parse(raw) catch {
    _ => abort("invalid column edit request")
  }
  guard request
    is {
      "sheet": String(sheet),
      "column": Number(column_number, ..),
      "count": Number(count_number, ..),
      ..
    } else {
    abort("column edit request needs sheet, column and count")
  }
  let column = @string.parse_int(column_number.to_string()[:]) catch {
    _ => abort("column must be an integer")
  }
  let count = @string.parse_int(count_number.to_string()[:]) catch {
    _ => abort("count must be an integer")
  }
  if sheet.is_empty() ||
    column < 1 ||
    column > 256 ||
    count < 1 ||
    count > 100 ||
    count > 256 - column + 1 {
    abort("column edit exceeds preview bounds")
  }
  let changed = if is_xlsx {
    let archive = @opc.open(read_file(args[3])) catch {
      error => abort("MoonLeaf XLSX open failed: \{Repr(error)}")
    }
    let (edited, changed) = try {
      if insert {
        @xlsx.insert_sheet_columns(archive, sheet, column, count)
      } else {
        @xlsx.delete_sheet_columns(archive, sheet, column, count)
      }
    } catch {
      error => abort("MoonLeaf XLSX column edit failed: \{Repr(error)}")
    }
    if changed > 0 {
      let copy = @opc.save(edited) catch {
        error => abort("MoonLeaf XLSX save failed: \{Repr(error)}")
      }
      let reopened = @opc.open(copy) catch {
        _ => abort("MoonLeaf column edited copy failed archive verification")
      }
      ignore(@xlsx.read(reopened)) catch {
        _ => abort("MoonLeaf column edited copy failed workbook verification")
      }
      write_file(args[5], copy)
    }
    changed
  } else {
    if sheet != "工作表1" {
      abort("unknown CSV sheet")
    }
    let source = @utf8.decode(Bytes::from_array(read_file(args[3]))) catch {
      _ => abort("invalid UTF-8")
    }
    let delimiter = if is_tsv { '\t' } else { ',' }
    let table = @csv.parse(source, delimiter~) catch {
      _ => abort("MoonLeaf delimited parse failed")
    }
    let (edited, changed) = try {
      if insert {
        (table.insert_columns(column, count), count)
      } else {
        table.delete_columns(column, count)
      }
    } catch {
      _ => abort("MoonLeaf delimited column edit failed")
    }
    if changed > 0 {
      write_file(args[5], verified_delimited_bytes(edited, source))
    }
    changed
  }
  let receipt : Json = {
    "contract": if insert {
      "moonleaf.insert-columns.v1"
    } else {
      "moonleaf.delete-columns.v1"
    },
    "sheet": sheet,
    "column": column,
    "requested_columns": count,
    "changed_columns": changed,
    "saved_copy": changed > 0,
    "source_unchanged": true,
  }
  println(receipt.stringify())
}

///|
/// Save a verified XLSX copy after hiding or showing selected whole rows.
/// The source path remains untouched so the caller can reopen it for undo.
fn set_rows_hidden(args : Array[String], hide : Bool) -> Unit {
  let operation = if hide { "hide-rows" } else { "show-rows" }
  if args.length() != 6 {
    abort("usage: moonleaf-preview \{operation} SOURCE NAME OUTPUT")
  }
  if !args[4].to_lower().has_suffix(".xlsx") {
    abort("row visibility requires XLSX")
  }
  let raw = read_stdin()
  if raw.length() > 16_384 {
    abort("row visibility request exceeds limit")
  }
  let request = @json.parse(raw) catch {
    _ => abort("invalid row visibility request")
  }
  guard request
    is {
      "sheet": String(sheet),
      "row": Number(row_number, ..),
      "count": Number(count_number, ..),
      ..
    } else {
    abort("row visibility request needs sheet, row and count")
  }
  let row = @string.parse_int(row_number.to_string()[:]) catch {
    _ => abort("row must be an integer")
  }
  let count = @string.parse_int(count_number.to_string()[:]) catch {
    _ => abort("count must be an integer")
  }
  if sheet.is_empty() ||
    row < 1 ||
    row > 10_000 ||
    count < 1 ||
    count > 100 ||
    count > 10_000 - row + 1 {
    abort("row visibility exceeds preview bounds")
  }
  let archive = @opc.open(read_file(args[3])) catch {
    error => abort("MoonLeaf XLSX open failed: \{Repr(error)}")
  }
  let (edited, changed) = try {
    if hide {
      @xlsx.hide_sheet_rows(archive, sheet, row, count)
    } else {
      @xlsx.show_sheet_rows(archive, sheet, row, count)
    }
  } catch {
    error => abort("MoonLeaf XLSX row visibility failed: \{Repr(error)}")
  }
  if changed > 0 {
    let copy = @opc.save(edited) catch {
      error => abort("MoonLeaf XLSX save failed: \{Repr(error)}")
    }
    let reopened = @opc.open(copy) catch {
      _ => abort("MoonLeaf row visibility copy failed archive verification")
    }
    ignore(@xlsx.read(reopened)) catch {
      _ => abort("MoonLeaf row visibility copy failed workbook verification")
    }
    write_file(args[5], copy)
  }
  let receipt : Json = {
    "contract": if hide {
      "moonleaf.hide-rows.v1"
    } else {
      "moonleaf.show-rows.v1"
    },
    "sheet": sheet,
    "row": row,
    "requested_rows": count,
    "changed_rows": changed,
    "saved_copy": changed > 0,
    "source_unchanged": true,
  }
  println(receipt.stringify())
}

///|
/// Save a verified XLSX copy with one existing row's cell formatting applied
/// to another existing row. The destination's cell values stay untouched.
fn copy_row_styles(args : Array[String]) -> Unit {
  if args.length() != 6 {
    abort("usage: moonleaf-preview copy-row-styles SOURCE NAME OUTPUT")
  }
  if !args[4].to_lower().has_suffix(".xlsx") {
    abort("row style copy requires XLSX")
  }
  let raw = read_stdin()
  if raw.length() > 16_384 {
    abort("row style copy request exceeds limit")
  }
  let request = @json.parse(raw) catch {
    _ => abort("invalid row style copy request")
  }
  guard request
    is {
      "sheet": String(sheet),
      "source_row": Number(source_number, ..),
      "destination_row": Number(destination_number, ..),
      ..
    } else {
    abort("row style copy needs sheet, source_row and destination_row")
  }
  let source_row = @string.parse_int(source_number.to_string()[:]) catch {
    _ => abort("source_row must be an integer")
  }
  let destination_row = @string.parse_int(destination_number.to_string()[:]) catch {
    _ => abort("destination_row must be an integer")
  }
  if sheet.is_empty() ||
    source_row < 1 ||
    source_row > 10_000 ||
    destination_row < 1 ||
    destination_row > 10_000 ||
    source_row == destination_row {
    abort("row style copy exceeds preview bounds")
  }
  let archive = @opc.open(read_file(args[3])) catch {
    error => abort("MoonLeaf XLSX open failed: \{Repr(error)}")
  }
  let (edited, changed) = @xlsx.copy_sheet_row_styles(
    archive, sheet, source_row, destination_row,
  ) catch {
    error => abort("MoonLeaf XLSX row style copy failed: \{Repr(error)}")
  }
  let copy = @opc.save(edited) catch {
    error => abort("MoonLeaf XLSX save failed: \{Repr(error)}")
  }
  let reopened = @opc.open(copy) catch {
    _ => abort("MoonLeaf row style copy failed archive verification")
  }
  let before = @xlsx.read(archive) catch {
    _ => abort("MoonLeaf source workbook failed verification")
  }
  let after = @xlsx.read(reopened) catch {
    _ => abort("MoonLeaf row style copy failed workbook verification")
  }
  if before.sheets.length() != after.sheets.length() {
    abort("MoonLeaf row style copy changed sheet count")
  }
  for index in 0..<before.sheets.length() {
    let original = before.sheets[index]
    let result = after.sheets[index]
    if original.name != result.name {
      abort("MoonLeaf row style copy changed sheet name")
    }
    for cell in original.cells {
      guard result.cells.any(candidate => {
        candidate.row == cell.row &&
        candidate.column == cell.column &&
        candidate.value == cell.value
      }) else {
        abort("MoonLeaf row style copy changed a cell value")
      }
    }
  }
  write_file(args[5], copy)
  let receipt : Json = {
    "contract": "moonleaf.copy-row-styles.v1",
    "sheet": sheet,
    "source_row": source_row,
    "destination_row": destination_row,
    "changed_formats": changed,
    "saved_copy": true,
    "source_unchanged": true,
  }
  println(receipt.stringify())
}

///|
fn ascii_fold(char : Char) -> Int {
  let code = char.to_int()
  if code >= 65 && code <= 90 {
    code + 32
  } else {
    code
  }
}

///|
/// Preserve the original character boundaries while matching ASCII letters
/// without case; other Unicode characters compare exactly.
fn replace_visible_text(
  value : String,
  find : String,
  replacement : String,
) -> String {
  let input : Array[Char] = value.iter().collect()
  let pattern : Array[Char] = find.iter().collect()
  let output = StringBuilder()
  let mut index = 0
  while index < input.length() {
    let mut matches = pattern.length() > 0 &&
      index + pattern.length() <= input.length()
    if matches {
      for offset in 0..<pattern.length() {
        if ascii_fold(input[index + offset]) != ascii_fold(pattern[offset]) {
          matches = false
          break
        }
      }
    }
    if matches {
      output.write_string(replacement)
      index += pattern.length()
    } else {
      output.write_char(input[index])
      index += 1
    }
  }
  output.to_string()
}

///|
fn replace_all(args : Array[String]) -> Unit {
  if args.length() != 6 {
    abort("usage: moonleaf-preview replace-all SOURCE NAME OUTPUT")
  }
  let payload = read_stdin()
  if payload.length() > 65_536 {
    abort("replace request exceeds limit")
  }
  let request = @json.parse(payload) catch {
    _ => abort("invalid replace request")
  }
  guard request
    is {
      "sheet": String(sheet),
      "find": String(find),
      "replace": String(replacement),
      ..
    } else {
    abort("replace request needs sheet, find and replace")
  }
  if find.is_empty() || find.length() > 256 || replacement.length() > 32_768 {
    abort("find or replacement text exceeds limit")
  }
  let source = args[3]
  let filename = args[4]
  let output = args[5]
  let bytes = read_file(source)
  let mut count = 0
  if filename.to_lower().has_suffix(".xlsx") {
    let session = @moonleaf.open_session(filename, bytes) catch {
      error => abort("MoonLeaf open failed: \{Repr(error)}")
    }
    guard session.scene() is WorkbookDocument(workbook) else {
      abort("MoonLeaf did not return a workbook")
    }
    let edits : Array[(Int, Int, String)] = []
    let mut found_sheet = false
    for candidate in workbook.sheets {
      if candidate.name == sheet {
        found_sheet = true
        for cell in candidate.cells {
          match cell.value {
            Text(text) | Number(text) => {
              let updated = replace_visible_text(text, find, replacement)
              if updated != text {
                edits.push((cell.row, cell.column, updated))
              }
            }
            _ => ()
          }
        }
      }
    }
    if !found_sheet {
      abort("unknown workbook sheet")
    }
    count = edits.length()
    if count > 0 {
      let edited = session.set_cells_text(sheet, edits) catch {
        error => abort("MoonLeaf batch edit failed: \{Repr(error)}")
      }
      let copy = edited.save_as_copy() catch {
        error => abort("MoonLeaf save failed: \{Repr(error)}")
      }
      write_file(output, copy.bytes())
    }
  } else if filename.to_lower().has_suffix(".csv") ||
    filename.to_lower().has_suffix(".tsv") {
    if sheet != "工作表1" {
      abort("unknown CSV sheet")
    }
    let text = @utf8.decode(Bytes::from_array(bytes)) catch {
      _ => abort("invalid UTF-8")
    }
    let delimiter = if filename.to_lower().has_suffix(".tsv") {
      '\t'
    } else {
      ','
    }
    let table = @csv.parse(text, delimiter~) catch {
      _ => abort("MoonLeaf delimited parse failed")
    }
    let rows = table.rows.map(row => {
      row.map(value => {
        let updated = replace_visible_text(value, find, replacement)
        if updated != value {
          count += 1
          safe_csv_text(updated)
        } else {
          updated
        }
      })
    })
    if count > 0 {
      let edited : @csv.Table = { rows, delimiter, }
      write_file(output, verified_delimited_bytes(edited, text))
    }
  } else {
    abort("unsupported spreadsheet format")
  }
  let result : Json = { "replaced_cells": count }
  println(result.stringify())
}

///|
fn sorted_delimited(
  table : @csv.Table,
  column : Int,
  descending : Bool,
  has_header : Bool,
) -> (@csv.Table, Int) {
  if column < 1 || column > 256 {
    abort("sort column is out of range")
  }
  let start = if has_header { 1 } else { 0 }
  if table.rows.length() <= start + 1 {
    return (table, 0)
  }
  let keys : Array[String] = []
  for row in table.rows[start:] {
    keys.push(row.get(column - 1).unwrap_or(""))
  }
  let order = @scene.sort_row_indices(keys, descending)
  let rows : Array[Array[String]] = []
  if has_header {
    rows.push(table.rows[0])
  }
  for index in order {
    rows.push(table.rows[start + index])
  }
  ({ rows, delimiter: table.delimiter, }, order.length())
}

///|
fn sort_file(args : Array[String]) -> Unit {
  if args.length() != 6 {
    abort("usage: moonleaf-preview sort SOURCE NAME OUTPUT")
  }
  let request = @json.parse(read_stdin()) catch {
    _ => abort("invalid sort request")
  }
  guard request
    is {
      "sheet": String(sheet),
      "column": Number(column_number, ..),
      "descending": direction,
      "has_header": header,
      ..
    } else {
    abort("sort request needs sheet, column, descending and has_header")
  }
  let column = @string.parse_int(column_number.to_string()[:]) catch {
    _ => abort("sort column must be an integer")
  }
  let descending = match direction {
    True => true
    False => false
    _ => abort("descending must be Boolean")
  }
  let has_header = match header {
    True => true
    False => false
    _ => abort("has_header must be Boolean")
  }
  let source = args[3]
  let filename = args[4]
  let output = args[5]
  let bytes = read_file(source)
  let mut count = 0
  if filename.to_lower().has_suffix(".xlsx") {
    let archive = @opc.open(bytes) catch {
      error => abort("MoonLeaf XLSX open failed: \{Repr(error)}")
    }
    let (sorted, sorted_rows) = @xlsx.sort_sheet_rows(
      archive, sheet, column, descending, has_header,
    ) catch {
      error => abort("MoonLeaf XLSX sort failed: \{Repr(error)}")
    }
    count = sorted_rows
    let copy = @opc.save(sorted) catch {
      error => abort("MoonLeaf XLSX save failed: \{Repr(error)}")
    }
    write_file(output, copy)
  } else if filename.to_lower().has_suffix(".csv") ||
    filename.to_lower().has_suffix(".tsv") {
    if sheet != "工作表1" {
      abort("unknown CSV sheet")
    }
    let text = @utf8.decode(Bytes::from_array(bytes)) catch {
      _ => abort("invalid UTF-8")
    }
    let delimiter = if filename.to_lower().has_suffix(".tsv") {
      '\t'
    } else {
      ','
    }
    let table = @csv.parse(text, delimiter~) catch {
      _ => abort("MoonLeaf delimited parse failed")
    }
    let (sorted, sorted_rows) = sorted_delimited(
      table, column, descending, has_header,
    )
    count = sorted_rows
    write_file(output, verified_delimited_bytes(sorted, text))
  } else {
    abort("unsupported spreadsheet format")
  }
  let result : Json = { "sorted_rows": count }
  println(result.stringify())
}

///|
/// Read-only filter for the PaiWork grid. Row indices refer to the original
/// workbook, so editing and citations still address the same cells.
fn filter_file(args : Array[String]) -> Unit {
  if args.length() != 5 {
    abort("usage: moonleaf-preview filter SOURCE NAME")
  }
  let request = @json.parse(read_stdin()) catch {
    _ => abort("invalid filter request")
  }
  guard request
    is {
      "sheet": String(sheet_name),
      "column": Number(column_number, ..),
      "operator": String(operator),
      "value": String(value),
      "has_header": header,
      ..
    } else {
    abort("filter request needs sheet, column, operator, value and has_header")
  }
  let column = @string.parse_int(column_number.to_string()[:]) catch {
    _ => abort("filter column must be an integer")
  }
  if column < 1 || column > 256 || value.length() > 256 {
    abort("filter column or value exceeds limit")
  }
  let has_header = match header {
    True => true
    False => false
    _ => abort("has_header must be Boolean")
  }
  let mode = match operator {
    "contains" => @scene.RowFilter::Contains
    "equals" => Equals
    "not_empty" => NotEmpty
    "empty" => Empty
    _ => abort("unknown filter operator")
  }
  if (operator == "contains" || operator == "equals") && value.is_empty() {
    abort("filter value must not be empty")
  }
  let filename = args[4]
  let scene = @moonleaf.open(filename, read_file(args[3])) catch {
    error => abort("MoonLeaf open failed: \{Repr(error)}")
  }
  guard scene is WorkbookDocument(workbook) else {
    abort("MoonLeaf did not return a workbook")
  }
  guard workbook.sheets.iter().find_first(sheet => sheet.name == sheet_name)
    is Some(sheet) else {
    abort("unknown workbook sheet")
  }
  let mut row_count = 0
  for cell in sheet.cells {
    if cell.row < 1 || cell.row > 10_000 || cell.column < 1 || cell.column > 256 {
      abort("spreadsheet filter exceeds row or column limit")
    }
    if cell.row > row_count {
      row_count = cell.row
    }
  }
  let values : Array[String] = []
  for _ in 0..<row_count {
    values.push("")
  }
  for cell in sheet.cells {
    if cell.column == column {
      values[cell.row - 1] = cell_text(cell.value)
    }
  }
  let indices = @scene.filter_row_indices(values, mode, value, has_header)
  let matched = if has_header && row_count > 0 {
    indices.length() - 1
  } else {
    indices.length()
  }
  let result : Json = {
    "row_indices": indices,
    "matched_rows": matched,
    "total_rows": row_count,
  }
  println(result.stringify())
}

///|
fn input_rows() -> Array[Array[@scene.CellValue]] {
  let raw = read_stdin()
  if raw.length() > 8_388_608 {
    abort("workbook JSON exceeds 8 Mi UTF-16 units")
  }
  let payload = @json.parse(raw) catch { _ => abort("invalid workbook JSON") }
  guard payload is { "rows": Array(items), .. } && items.length() <= 10_001 else {
    abort("missing or oversized workbook rows")
  }
  json_cell_rows(items)
}

///|
fn json_cell_rows(items : Array[Json]) -> Array[Array[@scene.CellValue]] {
  guard items.length() <= 10001 else { abort("workbook rows exceed bounds") }
  let rows : Array[Array[@scene.CellValue]] = []
  let mut total_cells = 0
  for item in items {
    guard item is Array(values) && values.length() <= 256 else {
      abort("invalid workbook row")
    }
    let row : Array[@scene.CellValue] = []
    for value in values {
      total_cells += 1
      if total_cells > 100_000 {
        abort("workbook exceeds 100000 cells")
      }
      row.push(
        match value {
          String(text) => Text(text)
          Number(number, ..) => Number(number.to_string())
          True => Boolean(true)
          False => Boolean(false)
          Null => Empty
          Object(fields) => {
            guard fields.get("formula") is Some(String(formula)) else {
              abort("formula cell requires explicit formula text")
            }
            let expression = formula
              .trim()
              .strip_prefix("=")
              .unwrap_or(formula.trim())
              .to_owned()
            guard !expression.is_empty() && expression.length() <= 2048 else {
              abort("formula cell expression must contain 1..2048 characters")
            }
            let cached = match fields.get("cached") {
              None => None
              Some(Number(number, ..)) if !number.is_inf() && !number.is_nan() =>
                Some(number.to_string())
              _ =>
                abort(
                  "formula cell cached value must be a finite number when supplied",
                )
            }
            Formula(expression~, cached~)
          }
          _ => abort("unsupported workbook cell")
        },
      )
    }
    rows.push(row)
  }
  rows
}

///|
fn recalculate_created_formulas(
  bytes : FixedArray[Byte],
  has_formulas : Bool,
) -> FixedArray[Byte] {
  if !has_formulas {
    return bytes
  }
  let archive = @opc.open(bytes) catch {
    error => abort("MoonLeaf formula workbook open failed: \{Repr(error)}")
  }
  let recalculated = @xlsx.recalculate(archive) catch {
    error =>
      abort("MoonLeaf formula workbook calculation failed: \{Repr(error)}")
  }
  @opc.save(recalculated) catch {
    error => abort("MoonLeaf formula workbook save failed: \{Repr(error)}")
  }
}

///|
fn safe_csv_text(value : String) -> String {
  @csv.safe_text(value)
}

///|
///
/// A CSV export must stay within the same bounds as MoonLeaf's reader. CSV
/// quoting can enlarge an otherwise valid workbook beyond that limit.
fn created_csv_bytes(
  rows : Array[Array[@scene.CellValue]],
) -> Result[FixedArray[Byte], String] {
  @csv.create(rows)
}

///|
/// Convert a sparse worksheet into CSV rows while retaining row positions.
fn sheet_csv_rows(
  sheet : @scene.Sheet,
) -> (Array[Array[@scene.CellValue]], Int, Int) {
  let rows : Array[Array[@scene.CellValue]] = []
  let mut cell_count = 0
  let mut max_column = 0
  let mut formula_count = 0
  for cell in sheet.cells {
    if cell.row < 1 || cell.row > 50_000 || cell.column < 1 || cell.column > 256 {
      abort("CSV sheet export exceeds row or column limit")
    }
    while rows.length() < cell.row {
      rows.push([])
    }
    let row = rows[cell.row - 1]
    while row.length() < cell.column {
      row.push(Empty)
      cell_count += 1
      if cell_count > 500_000 {
        abort("CSV sheet export exceeds cell limit")
      }
    }
    row[cell.column - 1] = cell.value
    if cell.column > max_column {
      max_column = cell.column
    }
    if cell.value is Formula(..) {
      formula_count += 1
    }
  }
  (rows, max_column, formula_count)
}

///|
/// Export one selected XLSX worksheet as a verified CSV copy. A formula is
/// exported as protected formula text because cached results can be stale.
fn export_sheet_csv(args : Array[String]) -> Unit {
  if args.length() != 7 {
    abort("usage: moonleaf-preview export-sheet-csv SOURCE NAME SHEET OUTPUT")
  }
  let source = args[3]
  let filename = args[4]
  let sheet_name = args[5]
  let output = args[6]
  if (
      !filename.to_lower().has_suffix(".xlsx") &&
      !filename.to_lower().has_suffix(".xls")
    ) ||
    sheet_name.is_empty() {
    abort("CSV sheet export requires XLSX or XLS and a sheet name")
  }
  let document = @moonleaf.open(filename, read_file(source)) catch {
    error => abort("MoonLeaf XLSX open failed: \{Repr(error)}")
  }
  guard document is WorkbookDocument(workbook) else {
    abort("MoonLeaf did not return a workbook")
  }
  let mut selected : @scene.Sheet? = None
  for sheet in workbook.sheets {
    if sheet.name == sheet_name {
      selected = Some(sheet)
      break
    }
  }
  guard selected is Some(sheet) else { abort("unknown XLSX sheet") }
  let (rows, max_column, formula_count) = sheet_csv_rows(sheet)
  let bytes = match created_csv_bytes(rows) {
    Ok(value) => value
    Err(message) => abort(message)
  }
  write_file(output, bytes)
  let receipt : Json = {
    "contract": "moonleaf.export-sheet-csv.v1",
    "sheet": sheet_name,
    "rows": rows.length(),
    "columns": max_column,
    "formulas_as_text": formula_count,
    "bytes": bytes.length(),
  }
  println(receipt.stringify())
}

///|
/// Preserve every delimited field as literal text. In particular, leading
/// zeroes, long identifiers and formula-looking values must survive Excel.
fn delimited_xlsx_rows(
  text : String,
  delimiter : Char,
) -> Array[Array[@scene.CellValue]] raise @csv.CsvError {
  let table = @csv.parse(text, delimiter~)
  table.rows.map(row => row.map(value => Text(value)))
}

///|
fn convert_delimited_xlsx(args : Array[String]) -> Unit {
  if args.length() != 7 {
    abort(
      "usage: moonleaf-preview convert-delimited-xlsx SOURCE NAME SHEET OUTPUT",
    )
  }
  let source = args[3]
  let filename = args[4]
  let sheet_name = args[5]
  let output = args[6]
  let lower = filename.to_lower()
  let delimiter = if lower.has_suffix(".csv") {
    ','
  } else if lower.has_suffix(".tsv") {
    '\t'
  } else {
    abort("MoonLeaf XLSX conversion requires CSV or TSV")
  }
  let text = @utf8.decode(Bytes::from_array(read_file(source))) catch {
    _ => abort("MoonLeaf delimited source is not UTF-8")
  }
  let rows = delimited_xlsx_rows(text, delimiter) catch {
    _ => abort("MoonLeaf delimited parse failed")
  }
  let bytes = @xlsx.create(rows, sheet_name~) catch {
    error => abort("MoonLeaf XLSX creation failed: \{Repr(error)}")
  }
  let reopened = @xlsx.read(@opc.open(bytes)) catch {
    error => abort("MoonLeaf XLSX verification failed: \{Repr(error)}")
  }
  if reopened.sheets.length() != 1 || reopened.sheets[0].name != sheet_name {
    abort("MoonLeaf XLSX sheet verification failed")
  }
  write_file(output, bytes)
  let mut columns = 0
  for row in rows {
    columns = columns.max(row.length())
  }
  let receipt : Json = {
    "contract": "moonleaf.convert-delimited-xlsx.v1",
    "sheet": sheet_name,
    "rows": rows.length(),
    "columns": columns,
    "all_cells_as_text": true,
    "bytes": bytes.length(),
  }
  println(receipt.stringify())
}

///|
fn create_file(args : Array[String]) -> Unit {
  if args.length() != 4 {
    abort("usage: moonleaf-preview create-xlsx|create-csv OUTPUT")
  }
  let rows = input_rows()
  if args[2] == "create-xlsx" {
    let bytes = @xlsx.create(rows) catch {
      error => abort("MoonLeaf XLSX creation failed: \{Repr(error)}")
    }
    write_file(
      args[3],
      recalculate_created_formulas(
        bytes,
        rows.any(row => row.any(value => value is Formula(..))),
      ),
    )
  } else if args[2] == "create-csv" {
    let bytes = match created_csv_bytes(rows) {
      Ok(value) => value
      Err(message) => abort(message)
    }
    write_file(args[3], bytes)
  } else {
    abort("unknown creation format")
  }
}

///|
fn create_workbook_file(args : Array[String]) -> Unit {
  guard args.length() == 4 else {
    abort("usage: moonleaf-preview create-workbook OUTPUT")
  }
  let raw = read_stdin()
  guard raw.length() <= 8388608 else {
    abort("workbook JSON exceeds 8 Mi UTF-16 units")
  }
  let payload = @json.parse(raw) catch { _ => abort("invalid workbook JSON") }
  guard payload is { "sheets": Array(values), .. } &&
    values.length() >= 1 &&
    values.length() <= 20 else {
    abort("workbook needs 1..20 sheets")
  }
  let sheets = values.map(value => {
    guard value is { "name": String(name), "rows": Array(rows), .. } else {
      abort("workbook sheet needs name and rows")
    }
    (name, json_cell_rows(rows))
  })
  let created = @xlsx.create_workbook(sheets) catch {
    _ => abort("MoonLeaf workbook creation failed")
  }
  let bytes = recalculate_created_formulas(
    created,
    sheets.any(sheet => {
      sheet.1.any(row => row.any(value => value is Formula(..)))
    }),
  )
  let archive = @opc.open(bytes) catch {
    _ => abort("MoonLeaf workbook ZIP verification failed")
  }
  let reopened = @xlsx.read(archive) catch {
    _ => abort("MoonLeaf workbook read verification failed")
  }
  guard reopened.sheets.length() == sheets.length() else {
    abort("MoonLeaf workbook sheet verification failed")
  }
  write_file(args[3], bytes)
}

///|
fn extract_docx(args : Array[String]) -> Unit {
  if args.length() != 5 {
    abort("usage: moonleaf-preview extract-docx SOURCE OUTPUT")
  }
  let document = @moonleaf.open("source.docx", read_file(args[3])) catch {
    error => abort("MoonLeaf DOCX open failed: \{Repr(error)}")
  }
  guard document is TextDocument(text_document) else {
    abort("MoonLeaf did not return a text document")
  }
  let content = text_document.plain_text()
  if content == "" {
    abort("DOCX contains no extractable text")
  }
  write_file(args[4], @utf8.encode(content).to_fixedarray())
}

///|
fn verified_docx_edit_copy(
  source : FixedArray[Byte],
  find : String,
  replacement : String,
) -> FixedArray[Byte] {
  let session = @moonleaf.open_session("source.docx", source) catch {
    error => abort("MoonLeaf DOCX open failed: \{Repr(error)}")
  }
  let edited = session.replace_text(find, replacement) catch {
    error => abort("MoonLeaf DOCX edit failed: \{Repr(error)}")
  }
  if !edited.is_dirty() {
    abort("DOCX find text was not present in editable Word paragraph text")
  }
  let copy = edited.save_as_copy() catch {
    error => abort("MoonLeaf DOCX save failed: \{Repr(error)}")
  }
  copy.bytes()
}

///|
fn verified_docx_paragraph_copy(
  source : FixedArray[Byte],
  paragraph_index : Int,
  expected_text : String,
  replacement : String,
) -> FixedArray[Byte] {
  let archive = @opc.open(source) catch {
    error => abort("MoonLeaf DOCX open failed: \{Repr(error)}")
  }
  let edited = @docx.replace_body_paragraph(
    archive, paragraph_index, expected_text, replacement,
  ) catch {
    error => abort("MoonLeaf DOCX paragraph edit failed: \{Repr(error)}")
  }
  if edited == archive {
    abort("DOCX paragraph text did not change")
  }
  let copy = @opc.save(edited) catch {
    error => abort("MoonLeaf DOCX save failed: \{Repr(error)}")
  }
  let reopened = @opc.open(copy) catch {
    error => abort("MoonLeaf DOCX reopen failed: \{Repr(error)}")
  }
  let verified = @docx.replace_body_paragraph(
    reopened, paragraph_index, replacement, replacement,
  ) catch {
    error =>
      abort("MoonLeaf DOCX paragraph verification failed: \{Repr(error)}")
  }
  if verified != reopened {
    abort("DOCX paragraph verification changed the copy")
  }
  copy
}

///|
/// Produce a verified DOCX copy with literal, case-sensitive replacement in
/// editable Word paragraph text, including adjacent simple runs. The source
/// is never modified.
fn edit_docx_copy(args : Array[String]) -> Unit {
  if args.length() != 5 {
    abort("usage: moonleaf-preview edit-docx-copy SOURCE OUTPUT")
  }
  let request_text = read_stdin()
  if request_text.length() > 65_536 {
    abort("DOCX edit request exceeds limit")
  }
  let request = @json.parse(request_text) catch {
    _ => abort("invalid DOCX edit request")
  }
  let (find, paragraph_index, expected_text, replacement) = match request {
    { "find": String(find), "replace": String(replacement), .. } =>
      (Some(find), None, None, replacement)
    {
      "paragraph_index": Number(index, ..),
      "expected_text": String(expected_text),
      "replace": String(replacement),
      ..
    } => {
      let ordinal = @string.parse_int(index.to_string()[:]) catch {
        _ => abort("paragraph_index must be an integer")
      }
      (None, Some(ordinal), Some(expected_text), replacement)
    }
    _ => abort("DOCX edit request needs find or paragraph index")
  }
  if replacement.length() > 32_768 ||
    (find is Some(value) && (value.is_empty() || value.length() > 256)) ||
    (expected_text is Some(value) && value.length() > 32_768) {
    abort("DOCX edit request exceeds limit")
  }
  for character in replacement {
    let code = character.to_int()
    if code < 0x20 && code != 0x09 {
      abort("DOCX replacement contains unsupported control character")
    }
  }
  let source = read_file(args[3])
  if source.length() > 8_000_000 {
    abort("DOCX source exceeds limit")
  }
  let copy = match (find, paragraph_index, expected_text) {
    (Some(find), _, _) => verified_docx_edit_copy(source, find, replacement)
    (_, Some(index), Some(expected)) =>
      verified_docx_paragraph_copy(source, index, expected, replacement)
    _ => abort("DOCX edit request is incomplete")
  }
  write_file(args[4], copy)
  let result : Json = {
    "contract": "moonleaf.docx-edit-copy.v1",
    "changed": true,
    "bytes": copy.length(),
  }
  println(result.stringify())
}

///|
fn optional_int_json(value : Int?) -> Json {
  match value {
    Some(number) => @json.to_json(number)
    None => Json::null()
  }
}

///|
fn optional_string_json(value : String?) -> Json {
  match value {
    Some(text) => @json.to_json(text)
    None => Json::null()
  }
}

///|
fn docx_run_json(run : @docx.RunMetadata, text_size : Ref[Int]) -> Json {
  text_size.val += run.text.length()
  if text_size.val > 200_000 {
    abort("DOCX preview exceeds text limit")
  }
  {
    "text": run.text,
    "bold": run.bold,
    "italic": run.italic,
    "underline": run.underline,
    "strike": run.strike,
    "font_size_half_points": optional_int_json(run.font_size_half_points),
    "font_ascii": optional_string_json(run.font_ascii),
    "font_east_asia": optional_string_json(run.font_east_asia),
    "color": optional_string_json(run.color),
    "highlight": optional_string_json(run.highlight),
    "hyperlink": optional_string_json(run.hyperlink),
  }
}

///|
fn docx_paragraph_json(
  paragraph : @docx.ParagraphInfo,
  text_size : Ref[Int],
) -> Json {
  if paragraph.runs.length() > 10_000 {
    abort("DOCX preview exceeds run limit")
  }
  let runs = paragraph.runs.map(run => docx_run_json(run, text_size))
  {
    "type": "paragraph",
    "runs": runs,
    "outline_level": optional_int_json(paragraph.outline_level),
    "list": match paragraph.list {
      Some(list) =>
        {
          "num_id": list.num_id,
          "level": list.level,
          "format": list.format,
          "label_template": list.label_template,
          "start": list.start,
        }
      None => Json::null()
    },
    "alignment": optional_string_json(paragraph.metadata.alignment),
    "spacing_before_twips": optional_int_json(
      paragraph.metadata.spacing_before_twips,
    ),
    "spacing_after_twips": optional_int_json(
      paragraph.metadata.spacing_after_twips,
    ),
    "left_indent_twips": optional_int_json(paragraph.metadata.left_indent_twips),
    "right_indent_twips": optional_int_json(
      paragraph.metadata.right_indent_twips,
    ),
    "first_line_twips": optional_int_json(paragraph.metadata.first_line_twips),
  }
}

///|
fn docx_table_json(
  table : @docx.TableInfo,
  text_size : Ref[Int],
  table_index? : Int,
) -> Json {
  if table.rows.length() > 2_000 {
    abort("DOCX preview exceeds table row limit")
  }
  let rows : Array[Json] = []
  for row_index, row in table.rows {
    if row.cells.length() > 100 {
      abort("DOCX preview exceeds table column limit")
    }
    let cells : Array[Json] = []
    for cell_index, cell in row.cells {
      if cell.paragraphs.length() > 1_000 {
        abort("DOCX preview exceeds cell paragraph limit")
      }
      let paragraphs : Array[Json] = []
      for paragraph_index, paragraph in cell.paragraphs {
        let value = docx_paragraph_json(paragraph, text_size)
        if value is Object(fields) {
          fields["paragraph_index"] = paragraph_index.to_json()
        }
        paragraphs.push(value)
      }
      cells.push({
        "cell_index": cell_index,
        "paragraphs": paragraphs,
        "grid_span": cell.grid_span,
        "vertical_merge": optional_string_json(cell.vertical_merge),
        "width_twips": optional_int_json(cell.width_twips),
        "margin_top_twips": optional_int_json(cell.margin_top_twips),
        "margin_right_twips": optional_int_json(cell.margin_right_twips),
        "margin_bottom_twips": optional_int_json(cell.margin_bottom_twips),
        "margin_left_twips": optional_int_json(cell.margin_left_twips),
        "vertical_alignment": optional_string_json(cell.vertical_alignment),
      })
    }
    rows.push({
      "row_index": row_index,
      "cells": cells,
      "height_twips": optional_int_json(row.height_twips),
      "height_rule": optional_string_json(row.height_rule),
    })
  }
  {
    "type": "table",
    "table_index": optional_int_json(table_index),
    "rows": rows,
    "grid_widths_twips": table.grid_widths_twips,
  }
}

///|
fn preview_docx(args : Array[String]) -> Unit {
  if args.length() != 4 {
    abort("usage: moonleaf-preview preview-docx SOURCE")
  }
  let archive = @opc.open(read_file(args[3])) catch {
    error => abort("MoonLeaf DOCX open failed: \{Repr(error)}")
  }
  let document = @docx.preview_document(archive) catch {
    error => abort("MoonLeaf DOCX preview failed: \{Repr(error)}")
  }
  if document.blocks.length() > 5_000 {
    abort("DOCX preview exceeds block limit")
  }
  let text_size = Ref(0)
  let blocks : Array[Json] = []
  let paragraph_index = Ref(0)
  let table_index = Ref(0)
  for block in document.blocks {
    blocks.push(
      docx_flow_block_json(block, text_size, paragraph_index, table_index~),
    )
  }
  let page_text_size = Ref(0)
  let page_paragraph_index = Ref(0)
  let pagination = @docx.paginate_document(archive) catch {
    error => abort("MoonLeaf DOCX pagination failed: \{Repr(error)}")
  }
  let pages : Array[Json] = []
  for index, page in pagination.pages {
    pages.push({
      "number": (index + 1).to_json(),
      "blocks": page.blocks
      .map(block => {
        docx_flow_block_json(block, page_text_size, page_paragraph_index)
      })
      .to_json(),
      "used_height_twips": page.used_height_twips.to_json(),
    })
  }
  let result : Json = {
    "contract": "moonleaf.docx-preview.v1",
    "blocks": blocks,
    "headers": document.headers,
    "footers": document.footers,
    "pages": pages.to_json(),
    "page_geometry": {
      "page_width_twips": pagination.page_width_twips.to_json(),
      "page_height_twips": pagination.page_height_twips.to_json(),
      "margin_top_twips": pagination.margin_top_twips.to_json(),
      "margin_right_twips": pagination.margin_right_twips.to_json(),
      "margin_bottom_twips": pagination.margin_bottom_twips.to_json(),
      "margin_left_twips": pagination.margin_left_twips.to_json(),
      "content_width_twips": pagination.content_width_twips.to_json(),
      "content_height_twips": pagination.content_height_twips.to_json(),
    },
  }
  println(result.stringify())
}

///|
fn extract_pdf(args : Array[String]) -> Unit {
  if args.length() != 5 && args.length() != 6 {
    abort("usage: moonleaf-preview extract-pdf SOURCE OUTPUT [MAX_BYTES]")
  }
  let max_bytes = if args.length() == 6 {
    @string.parse_int(args[5][:]) catch {
      _ => abort("invalid PDF MAX_BYTES")
    }
  } else {
    8_000_000
  }
  let extracted = @pdf_text.extract_with_details(read_file(args[3]), max_bytes~) catch {
    error => abort("MoonLeaf PDF extraction failed: \{Repr(error)}")
  }
  write_file(args[4], @utf8.encode(extracted.text).to_fixedarray())
  let receipt : Json = {
    "contract": "moonleaf.pdf-text-extraction.v1",
    "extraction_warnings": extracted.extraction_warnings,
    "checksum_verification": extracted.checksum_verification,
    "truncated_pages": extracted.truncated_pages,
  }
  println(receipt.stringify())
}

///|
fn parse_delimited(args : Array[String]) -> Unit {
  if args.length() != 4 {
    abort("usage: moonleaf-preview parse-delimited SOURCE")
  }
  let source = args[3]
  let lower = source.to_lower()
  let delimiter = if lower.has_suffix(".csv") {
    ','
  } else if lower.has_suffix(".tsv") {
    '\t'
  } else {
    abort("MoonLeaf delimited source must end in .csv or .tsv")
  }
  let content = @utf8.decode(Bytes::from_array(read_file(source))) catch {
    _ => abort("MoonLeaf delimited source is not UTF-8")
  }
  let table = @csv.parse(content, delimiter~) catch {
    _ => abort("MoonLeaf delimited parse failed")
  }
  let result : Json = { "rows": table.rows }
  println(result.stringify())
}

///|
fn main {
  let args = cli_args()
  if args.length() >= 3 && args[2] == "edit-value" {
    edit_value(args)
  } else if args.length() >= 3 && args[2] == "recalculate" {
    recalculate_file(args)
  } else if args.length() >= 3 && args[2] == "replace-all" {
    replace_all(args)
  } else if args.length() >= 3 && args[2] == "paste-range" {
    paste_range(args)
  } else if args.length() >= 3 && args[2] == "clear-range" {
    clear_range(args)
  } else if args.length() >= 3 && args[2] == "format-wrap" {
    format_wrap(args)
  } else if args.length() >= 3 && args[2] == "format-font" {
    format_font(args)
  } else if args.length() >= 3 && args[2] == "format-align" {
    format_align(args)
  } else if args.length() >= 3 && args[2] == "format-number" {
    format_number(args)
  } else if args.length() >= 3 && args[2] == "insert-rows" {
    edit_rows(args, true)
  } else if args.length() >= 3 && args[2] == "delete-rows" {
    edit_rows(args, false)
  } else if args.length() >= 3 && args[2] == "insert-columns" {
    edit_columns(args, true)
  } else if args.length() >= 3 && args[2] == "delete-columns" {
    edit_columns(args, false)
  } else if args.length() >= 3 && args[2] == "hide-rows" {
    set_rows_hidden(args, true)
  } else if args.length() >= 3 && args[2] == "show-rows" {
    set_rows_hidden(args, false)
  } else if args.length() >= 3 && args[2] == "copy-row-styles" {
    copy_row_styles(args)
  } else if args.length() >= 3 && args[2] == "sort" {
    sort_file(args)
  } else if args.length() >= 3 && args[2] == "filter" {
    filter_file(args)
  } else if args.length() >= 3 && args[2] == "table-explore" {
    table_explore(args)
  } else if args.length() >= 3 && args[2] == "pivot-summary" {
    pivot_summary_copy(args)
  } else if args.length() >= 3 && args[2] == "parse-delimited" {
    parse_delimited(args)
  } else if args.length() >= 3 && args[2] == "export-sheet-csv" {
    export_sheet_csv(args)
  } else if args.length() >= 3 && args[2] == "convert-delimited-xlsx" {
    convert_delimited_xlsx(args)
  } else if args.length() >= 3 && args[2] == "extract-pdf" {
    extract_pdf(args)
  } else if args.length() >= 3 && args[2] == "extract-docx" {
    extract_docx(args)
  } else if args.length() >= 3 && args[2] == "extract-pptx" {
    extract_pptx(args)
  } else if args.length() >= 3 && args[2] == "edit-docx-copy" {
    edit_docx_copy(args)
  } else if args.length() >= 3 && args[2] == "preview-docx" {
    preview_docx(args)
  } else if args.length() >= 3 && args[2] == "edit-docx-structure-copy" {
    edit_docx_structure_copy(args)
  } else if args.length() >= 3 && args[2] == "preview-pptx" {
    preview_pptx(args)
  } else if args.length() >= 3 && args[2] == "edit-pptx-copy" {
    edit_pptx_copy(args)
  } else if args.length() >= 3 &&
    (args[2] == "create-xlsx" || args[2] == "create-csv") {
    create_file(args)
  } else if args.length() >= 3 && args[2] == "create-workbook" {
    create_workbook_file(args)
  } else if args.length() >= 3 && args[2] == "create-pptx" {
    create_pptx_file(args)
  } else if args.length() >= 3 && args[2] == "edit" {
    edit(args)
  } else if args.length() >= 3 {
    let filename = if args.length() > 3 { args[3] } else { args[2] }
    preview(args[2], filename)
  } else {
    abort("usage: moonleaf-preview FILE [DISPLAY_NAME]")
  }
}
