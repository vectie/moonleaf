///|
extern "js" fn read_file(path : String) -> FixedArray[Byte] =
  #|path => { const fs = require('node:fs'); const fd = fs.openSync(path, fs.constants.O_RDONLY | fs.constants.O_NONBLOCK); try { const s = fs.fstatSync(fd); if (!s.isFile() || s.size > 8388608) throw Error('Expected a regular file no larger than 8 MiB'); const b = fs.readFileSync(fd); if (b.length > 8388608) throw Error('File exceeds 8 MiB'); return Array.from(b); } finally { fs.closeSync(fd); } }

///|
extern "js" fn write_bytes(bytes : FixedArray[Byte]) -> Unit =
  #|bytes => require('node:fs').writeFileSync(1, Buffer.from(bytes))

///|
extern "js" fn diagnostic(text : String) -> Unit =
  #|text => console.error(text)

///|
extern "js" fn report_error(text : String) -> Unit =
  #|text => { console.error(text); process.exitCode = 1; }

///|
fn read_text(path : String) -> String raise {
  @utf8.decode(Bytes::from_array(read_file(path)))
}

///|
fn run() -> Unit raise {
  let args = @env.args()
  guard args.length() == 6 &&
    args[2] != "-" &&
    args[3] != "-" &&
    ["csv", "json", "xlsx", "report"].contains(args[5]) else {
    fail(
      "usage: node xlsx-table.js SOURCE.xlsx SELECTION.json QUERY.json|- csv|json|xlsx|report",
    )
  }
  let spec = read_text(args[3])
  if spec.length() > 65536 {
    fail("Selection exceeds 65536 text units")
  }
  guard @json.parse(spec) is Object(fields) &&
    fields.length() == 3 &&
    fields.get("sheet") is Some(String(sheet_name)) &&
    fields.get("range") is Some(String(range)) &&
    fields.get("header") is Some(header_json) else {
    fail("Selection requires exactly sheet, range and header")
  }
  let header : @jsontable.XlsxHeader = match header_json {
    String("first_row") => FirstRow
    Array(names) =>
      Columns(
        names.map(name => {
          guard name is String(text) else {
            fail("Header names must be strings")
          }
          text
        }),
      )
    _ => fail("header must be first_row or an explicit array of column names")
  }
  let archive = @opc.open_with_policy(read_file(args[2]), {
    ..@opc.ArchivePolicy::default(),
    max_compressed_input_bytes: 8388608,
    max_entry_compressed_bytes: 8388608,
    max_entry_uncompressed_bytes: 8388608,
    max_total_uncompressed_bytes: 16777216,
  })
  let imported = @jsontable.extract_xlsx(archive, sheet_name~, range~, header~)
  let (table, source_rows, matched_rows) = if args[4] == "-" {
    (imported.table, imported.source_rows, imported.table.rows.length())
  } else {
    let result = imported.table.query(
      @jsontable.parse_query_recipe(read_text(args[4])),
    )
    (
      result.table,
      result.source_rows.map(row => imported.source_rows[row - 1]),
      result.matched_rows,
    )
  }
  let report : Json = {
    "sheet": sheet_name,
    "range": range,
    "header": header_json,
    "input_rows": imported.table.rows.length(),
    "matched_rows": matched_rows,
    "output_rows": table.rows.length(),
    "output_columns": table.columns,
    "worksheet_rows": source_rows,
    "warnings": imported.warnings,
  }
  // Serialize before any dataset bytes: invalid selection/query/export is atomic.
  let bytes = match args[5] {
    "xlsx" => table.export_xlsx()
    "csv" => @utf8.encode(table.export_csv() + "\n").to_fixedarray()
    "json" =>
      @utf8.encode(table.export_json(omit_empty=true) + "\n").to_fixedarray()
    _ => @utf8.encode(report.stringify() + "\n").to_fixedarray()
  }
  diagnostic(report.stringify())
  write_bytes(bytes)
}

///|
fn main {
  run() catch {
    error => report_error("MoonLeaf XLSX table import failed: \{Repr(error)}")
  }
}
