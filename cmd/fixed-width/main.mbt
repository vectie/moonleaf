///|
extern "js" fn read_bytes(path : String, limit : Int32) -> FixedArray[Byte] =
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
fn run() -> Unit raise {
  let args = @env.args()
  guard (args.length() == 5 && args[2] == "inspect") ||
    (
      args.length() == 9 &&
      args[2] == "export" &&
      ["csv", "json", "xlsx"].contains(args[7])
    ) else {
    fail(
      "usage: node fixed-width.js inspect INPUT SCHEMA.json | export INPUT SCHEMA.json SOURCE_SHA256 QUERY.json|- csv|json|xlsx FRESH_OUTPUT",
    )
  }
  let input = read_bytes(args[3], 4_000_000)
  let schema_bytes = read_bytes(args[4], 65_536)
  let schema_text = @utf8.decode(Bytes::from_array(schema_bytes))
  let imported = @jsontable.parse_fixed_width(
    @utf8.decode(Bytes::from_array(input)),
    @jsontable.parse_fixed_width_schema(schema_text),
  )
  if args[2] == "inspect" {
    let report : Json = {
      "schema": "moonleaf.fixed-width-inspect.v1",
      "source_sha256": sha256(input),
      "schema_sha256": sha256(schema_bytes),
      "columns": imported.table.columns,
      "rows": imported.table.rows.length(),
      "source_lines": imported.source_lines,
      "skipped_lines": imported.skipped_lines,
      "preview": @json.parse(imported.table.export_json()),
      "warnings": fixed_warnings(),
    }
    println(report.stringify())
    return
  }
  if args[5] != sha256(input) {
    fail("Source SHA-256 changed or mismatched; inspect this source again")
  }
  let query_bytes = if args[6] == "-" {
    None
  } else {
    Some(read_bytes(args[6], 65_536))
  }
  let query_text = match query_bytes {
    None => ""
    Some(bytes) => @utf8.decode(Bytes::from_array(bytes))
  }
  let (table, positions, matched_rows) = if query_bytes is None {
    (
      imported.table,
      Array::makei(imported.table.rows.length(), i => i + 1),
      imported.table.rows.length(),
    )
  } else {
    let result = imported.table.query(@jsontable.parse_query_recipe(query_text))
    (result.table, result.source_rows, result.matched_rows)
  }
  let output = match args[7] {
    "xlsx" => table.export_xlsx()
    "csv" => @utf8.encode(table.export_csv() + "\n").to_fixedarray()
    _ => @utf8.encode(table.export_json() + "\n").to_fixedarray()
  }
  write_copy(args[8], output)
  let report : Json = {
    "schema": "moonleaf.fixed-width-export.v1",
    "source_sha256": sha256(input),
    "query_sha256": match query_bytes {
      None => Json::null()
      Some(bytes) => Json::string(sha256(bytes))
    },
    "output_sha256": sha256(output),
    "schema_sha256": sha256(schema_bytes),
    "import_schema": @json.parse(schema_text),
    "skipped_lines": imported.skipped_lines,
    "query": if query_bytes is None {
      Json::null()
    } else {
      @json.parse(query_text)
    },
    "format": args[7],
    "input_rows": imported.table.rows.length(),
    "matched_rows": matched_rows,
    "output_rows": table.rows.length(),
    "output_columns": table.columns,
    "source_lines": positions.map(position => {
      imported.source_lines[position - 1]
    }),
    "readback_equal": true,
    "warnings": fixed_warnings(),
  }
  println(report.stringify())
}

///|
fn fixed_warnings() -> Array[String] {
  [
    "Printable ASCII fixed-width records only. Column widths are adjacent ASCII positions; tabs, non-ASCII and ragged rows are refused. Skipped lines are explicitly reported.",
    "All values remain literal text; only requested edge spaces are trimmed. No numeric or formula inference. CSV applications may interpret formula-looking text; XLSX uses inline strings.",
    "This is a new dataset, not fixed-width writeback, Office fidelity or document-session render verification. Keep source, schema and query digests with output.",
  ]
}

///|
fn main {
  run() catch {
    error => report_error("MoonLeaf fixed-width import failed: \{Repr(error)}")
  }
}
