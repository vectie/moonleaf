///|
/// Node adapter for MoonLeaf's neutral spreadsheet scene.
extern "js" fn read_file(path : String) -> FixedArray[Byte] = "(path) => Array.from(require('node:fs').readFileSync(path))"

///|
extern "js" fn write_file(path : String, bytes : FixedArray[Byte]) -> Unit = "(path, bytes) => require('node:fs').writeFileSync(path, Buffer.from(bytes), {flag: 'wx', mode: 0o600})"

///|
extern "js" fn read_stdin() -> String = "() => require('node:fs').readFileSync(0, 'utf8')"

///|
extern "js" fn report_error(message : String) -> Unit = "(message) => console.error(message)"

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
fn sheet_json(
  sheet : @scene.Sheet,
  total : Ref[Int],
  text_size : Ref[Int],
) -> Json {
  let rows : Array[Array[String]] = []
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
    text_size.val += value.length()
    if text_size.val > 2_000_000 {
      abort("spreadsheet preview exceeds text limit")
    }
    row[cell.column - 1] = value
  }
  { "name": sheet.name, "rows": rows }
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
  guard scene is @scene.Document::WorkbookDocument(workbook) else {
    abort("MoonLeaf did not return a workbook")
  }
  if workbook.sheets.length() > 20 {
    abort("spreadsheet preview exceeds sheet limit")
  }
  let total = Ref(0)
  let text_size = Ref(0)
  let sheets = workbook.sheets.map(sheet => sheet_json(sheet, total, text_size))
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
    let serialized = if text.has_prefix("\u{FEFF}") {
      "\u{FEFF}" + edited.serialize()
    } else {
      edited.serialize()
    }
    write_file(output, @utf8.encode(serialized).to_fixedarray())
  } else {
    abort("unsupported spreadsheet format")
  }
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
    guard session.scene() is @scene.Document::WorkbookDocument(workbook) else {
      abort("MoonLeaf did not return a workbook")
    }
    let edits : Array[(Int, Int, String)] = []
    let mut found_sheet = false
    for candidate in workbook.sheets {
      if candidate.name == sheet {
        found_sheet = true
        for cell in candidate.cells {
          match cell.value {
            @scene.Text(text) | @scene.Number(text) => {
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
      let serialized = if text.has_prefix("\u{FEFF}") {
        "\u{FEFF}" + edited.serialize()
      } else {
        edited.serialize()
      }
      if serialized.length() > 2_097_152 {
        abort("edited delimited file exceeds 2 MiB")
      }
      write_file(output, @utf8.encode(serialized).to_fixedarray())
    }
  } else {
    abort("unsupported spreadsheet format")
  }
  let result : Json = { "replaced_cells": count }
  println(result.stringify())
}

///|
fn input_rows() -> Array[Array[@scene.CellValue]] {
  let raw = read_stdin()
  if raw.length() > 2_097_152 {
    abort("workbook JSON exceeds 2 MB")
  }
  let payload = @json.parse(raw) catch { _ => abort("invalid workbook JSON") }
  guard payload is { "rows": Array(items), .. } && items.length() <= 10_001 else {
    abort("missing or oversized workbook rows")
  }
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
          String(text) => @scene.Text(text)
          Number(number, ..) => @scene.Number(number.to_string())
          Null => @scene.Empty
          _ => abort("unsupported workbook cell")
        },
      )
    }
    rows.push(row)
  }
  rows
}

///|
fn safe_csv_text(value : String) -> String {
  let mut first = None
  for char in value.iter() {
    if char != ' ' &&
      char != '\t' &&
      char != '\u{FEFF}' &&
      char != '\r' &&
      char != '\n' {
      first = Some(char)
      break
    }
  }
  match first {
    Some('=') | Some('+') | Some('-') | Some('@') => "'" + value
    _ => value
  }
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
    write_file(args[3], bytes)
  } else if args[2] == "create-csv" {
    let csv_rows = rows.map(row => {
      row.map(value => {
        match value {
          @scene.Text(text) | @scene.Number(text) | @scene.Error(text) =>
            safe_csv_text(text)
          @scene.Boolean(flag) => if flag { "TRUE" } else { "FALSE" }
          @scene.Empty => ""
          @scene.Formula(expression~, ..) => safe_csv_text("=" + expression)
        }
      })
    })
    let table : @csv.Table = { rows: csv_rows, delimiter: ',', }
    write_file(
      args[3],
      @utf8.encode("\u{FEFF}" + table.serialize_quoted() + "\r\n").to_fixedarray(),
    )
  } else {
    abort("unknown creation format")
  }
}

///|
fn extract_docx(args : Array[String]) -> Unit {
  if args.length() != 5 {
    abort("usage: moonleaf-preview extract-docx SOURCE OUTPUT")
  }
  let document = @moonleaf.open("source.docx", read_file(args[3])) catch {
    error => abort("MoonLeaf DOCX open failed: \{Repr(error)}")
  }
  guard document is @scene.Document::TextDocument(text_document) else {
    abort("MoonLeaf did not return a text document")
  }
  let content = text_document.plain_text()
  if content == "" {
    abort("DOCX contains no extractable text")
  }
  write_file(args[4], @utf8.encode(content).to_fixedarray())
}

///|
fn extract_pdf(args : Array[String]) -> Unit {
  if args.length() != 5 {
    abort("usage: moonleaf-preview extract-pdf SOURCE OUTPUT")
  }
  let content = @pdf_text.extract(read_file(args[3])) catch {
    error => abort("MoonLeaf PDF extraction failed: \{Repr(error)}")
  }
  write_file(args[4], @utf8.encode(content).to_fixedarray())
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
  let args = @env.args()
  if args.length() >= 3 && args[2] == "replace-all" {
    replace_all(args)
  } else if args.length() >= 3 && args[2] == "parse-delimited" {
    parse_delimited(args)
  } else if args.length() >= 3 && args[2] == "extract-pdf" {
    extract_pdf(args)
  } else if args.length() >= 3 && args[2] == "extract-docx" {
    extract_docx(args)
  } else if args.length() >= 3 &&
    (args[2] == "create-xlsx" || args[2] == "create-csv") {
    create_file(args)
  } else if args.length() >= 3 && args[2] == "edit" {
    edit(args)
  } else if args.length() >= 3 {
    let filename = if args.length() > 3 { args[3] } else { args[2] }
    preview(args[2], filename)
  } else {
    abort("usage: moonleaf-preview FILE [DISPLAY_NAME]")
  }
}
