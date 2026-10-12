///|
extern "js" fn read_bytes(path : String, limit : Int) -> FixedArray[Byte] =
  #|(path, limit) => { const fs = require('node:fs'); const fd = fs.openSync(path, fs.constants.O_RDONLY | fs.constants.O_NONBLOCK); try { const s = fs.fstatSync(fd); if (!s.isFile() || s.size > limit) throw Error('Expected bounded regular file'); const b = fs.readFileSync(fd); if (b.length > limit) throw Error('Input exceeds byte limit'); return Array.from(b); } finally { fs.closeSync(fd); } }

///|
extern "js" fn sha256(bytes : FixedArray[Byte]) -> String =
  #|bytes => require('node:crypto').createHash('sha256').update(Buffer.from(bytes)).digest('hex')

///|
extern "js" fn write_copy(path : String, bytes : FixedArray[Byte]) -> Unit =
  #|(path, bytes) => { const fs = require('node:fs'); const b = Buffer.from(bytes); fs.writeFileSync(path, b, {flag:'wx', mode:0o600}); if (!fs.readFileSync(path).equals(b)) throw Error('Output readback differs'); }

///|
extern "js" fn report_error(message : String) -> Unit =
  #|message => { console.error(message); process.exitCode = 1; }

///|
fn read_text(path : String, limit : Int) -> String raise {
  @utf8.decode(Bytes::from_array(read_bytes(path, limit)))
}

///|
fn run() -> Unit raise {
  let args = @env.args()
  guard args.length() == 7 && ["csv", "json", "xlsx"].contains(args[5]) else {
    fail(
      "usage: node json-lines.js INPUT.json MAPPING.json QUERY.json|- csv|json|xlsx FRESH_OUTPUT",
    )
  }
  let input = read_bytes(args[2], 8_388_608)
  let mapping_bytes = read_bytes(args[3], 65_536)
  let mapping_text = @utf8.decode(Bytes::from_array(mapping_bytes))
  let mapping = @jsontable.parse_json_line_spec(mapping_text)
  let imported = @jsontable.parse_json_lines(
    @utf8.decode(Bytes::from_array(input)),
    mapping,
  )
  let query_text = if args[4] == "-" { "" } else { read_text(args[4], 65_536) }
  let query_json = if args[4] == "-" {
    Json::null()
  } else {
    @json.parse(query_text)
  }
  let (table, positions, matched_rows) = if args[4] == "-" {
    (
      imported.table,
      Array::makei(imported.table.rows.length(), i => i + 1),
      imported.table.rows.length(),
    )
  } else {
    let selected = imported.table.query(
      @jsontable.parse_query_recipe(query_text),
    )
    (selected.table, selected.source_rows, selected.matched_rows)
  }
  let locators : Array[Json] = positions.map(position => {
    let source = imported.table.rows[position - 1]
    guard source[0] is Number(parent) && source[1] is Number(item) else {
      fail("Internal row locator missing")
    }
    { "parent_row": @json.parse(parent), "item_row": @json.parse(item) }
  })
  let output = match args[5] {
    "xlsx" => table.export_xlsx()
    "csv" => @utf8.encode(table.export_csv() + "\n").to_fixedarray()
    _ => @utf8.encode(table.export_json(omit_empty=true) + "\n").to_fixedarray()
  }
  write_copy(args[6], output)
  let report : Json = {
    "schema": "moonleaf.json-lines-export.v1",
    "source_sha256": sha256(input),
    "mapping_sha256": sha256(mapping_bytes),
    "output_sha256": sha256(output),
    "mapping": @json.parse(mapping_text),
    "query": query_json,
    "format": args[5],
    "parent_count": imported.parent_count,
    "empty_parent_rows": imported.empty_parent_rows,
    "expanded_rows": imported.table.rows.length(),
    "matched_rows": matched_rows,
    "output_rows": table.rows.length(),
    "output_columns": table.columns,
    "source_rows": locators,
    "readback_equal": true,
    "warnings": [
      "Only one explicitly selected child-object array is expanded. Empty arrays are skipped and listed; no pagination, recursive flattening, totals or source-completeness claim.",
      "Row locators are one-based positions within this exact source and mapping, not physical lines or business keys. Duplicate records/items are retained. Keep this report with the output.",
      "JSON omits missing/empty-converted cells and has no empty-table schema. CSV loses types and may be interpreted as formulas by spreadsheet apps. XLSX is a new typed value workbook, not an original-document rewrite or Office-fidelity claim.",
    ],
  }
  println(report.stringify())
}

///|
fn main {
  run() catch {
    error =>
      report_error("MoonLeaf JSON line-item import failed: \{Repr(error)}")
  }
}
