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
  guard (args.length() == 4 && args[2] == "list") ||
    (
      args.length() == 9 &&
      args[2] == "export" &&
      ["csv", "json", "xlsx"].contains(args[7])
    ) else {
    fail(
      "usage: node markdown-tables.js list INPUT.md | export INPUT.md TABLE_ID SOURCE_SHA256 QUERY.json|- csv|json|xlsx FRESH_OUTPUT",
    )
  }
  let input = read_bytes(args[3], 8_388_608)
  if args[2] == "export" && args[5] != sha256(input) {
    fail(
      "Source SHA-256 changed or mismatched; list and review this source again",
    )
  }
  let tables = @jsontable.parse_markdown_tables(
    @utf8.decode(Bytes::from_array(input)),
  )
  if args[2] == "list" {
    let candidates : Array[Json] = tables.map(item => {
      "id": item.id,
      "header_line": item.header_line,
      "separator_line": item.separator_line,
      "columns": item.table.columns,
      "rows": item.table.rows.length(),
      "source_lines": item.source_lines,
    })
    let report : Json = {
      "schema": "moonleaf.markdown-tables-list.v1",
      "source_sha256": sha256(input),
      "tables": candidates,
      "warnings": markdown_warnings(),
    }
    println(report.stringify())
    return
  }
  let mut selected : @jsontable.MarkdownTable? = None
  for item in tables {
    if item.id == args[4] {
      selected = Some(item)
    }
  }
  guard selected is Some(imported) else {
    fail("Unknown table ID; list this exact source first")
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
    "schema": "moonleaf.markdown-table-export.v1",
    "source_sha256": sha256(input),
    "query_sha256": match query_bytes {
      None => Json::null()
      Some(bytes) => Json::string(sha256(bytes))
    },
    "output_sha256": sha256(output),
    "table_id": imported.id,
    "header_line": imported.header_line,
    "separator_line": imported.separator_line,
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
    "warnings": markdown_warnings(),
  }
  println(report.stringify())
}

///|
fn markdown_warnings() -> Array[String] {
  [
    "Bounded standalone pipe-table syntax only; not a full Markdown renderer. Fenced and indented code is skipped. HTML blocks, lists and blockquotes are not interpreted.",
    "All cells are literal text after edge whitespace and pipe/backslash escape handling; inline code, links, emphasis, entities and HTML remain literal. Unescaped pipes split cells even in backticks. No number or formula inference.",
    "Table IDs and one-based physical line numbers belong to this exact source digest. Re-list a changed source; no Markdown writeback or source-completeness claim.",
    "CSV loses type guarantees and spreadsheet apps may interpret formula-looking text. Prefer XLSX for literal text. A new dataset and byte readback are not document-session render verification or Office fidelity.",
  ]
}

///|
fn main {
  run() catch {
    error =>
      report_error("MoonLeaf Markdown table import failed: \{Repr(error)}")
  }
}
