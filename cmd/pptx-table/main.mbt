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
fn read_text(path : String, limit : Int32) -> String raise {
  @utf8.decode(Bytes::from_array(read_bytes(path, limit)))
}

///|
fn run() -> Unit raise {
  let args = @env.args()
  guard (args.length() == 4 && args[2] == "inspect") ||
    (
      args.length() == 8 &&
      args[2] == "export" &&
      ["csv", "json", "xlsx"].contains(args[6])
    ) else {
    fail(
      "usage: node pptx-table.js inspect SOURCE.pptx | export SOURCE.pptx SELECTION.json QUERY.json|- csv|json|xlsx FRESH_OUTPUT",
    )
  }
  let bytes = read_bytes(args[3], 8_388_608)
  let digest = sha256(bytes)
  let archive = @opc.open_with_policy(bytes, {
    ..@opc.ArchivePolicy::default(),
    max_compressed_input_bytes: 8_388_608,
    max_entry_compressed_bytes: 8_388_608,
    max_entry_uncompressed_bytes: 8_388_608,
    max_total_uncompressed_bytes: 16_777_216,
  })
  if args[2] == "inspect" {
    let tables = @pptx.read_tables(archive).map(table => {
      let refusal : Json = match table.refusal {
        Some(reason) => Json::string(reason)
        None => Json::null()
      }
      let item : Json = {
        "id": table.id,
        "slide_number": table.slide_number,
        "part": table.part,
        "shape_id": table.shape_id,
        "hidden_slide": table.hidden_slide,
        "rows": table.rows.length(),
        "columns": if table.rows.is_empty() {
          0
        } else {
          table.rows[0].length()
        },
        "first_row": if table.rows.is_empty() {
          []
        } else {
          table.rows[0]
        },
        "refusal": refusal,
      }
      item
    })
    let report : Json = {
      "schema": "moonleaf.pptx-tables.v1",
      "source_sha256": digest,
      "tables": tables,
      "warnings": [
        "Only ordinary slide tables are listed, including groups and hidden slides. Notes, masters, layouts and other objects are not imported. IDs belong to this exact source SHA-256. A null refusal means the text subset is importable, not Office fidelity or factual verification.",
      ],
    }
    println(report.stringify())
    return
  }
  let selection = @json.parse(read_text(args[4], 65_536))
  guard selection is Object(fields) &&
    fields.length() == 4 &&
    selection
    is {
      "version": Number(1, ..),
      "source_sha256": String(expected_digest),
      "table": String(table_id),
      "header": header_json,
      ..
    } else {
    fail(
      "selection requires exactly version:1, source_sha256, table and header",
    )
  }
  if expected_digest != digest {
    fail("source SHA-256 differs from inspected source; inspect again")
  }
  let header : @jsontable.PptxHeader = match header_json {
    String("first_row") => FirstSlideTableRow
    Array(names) =>
      SlideTableColumns(
        names.map(name => {
          guard name is String(text) else {
            fail("header names must be strings")
          }
          text
        }),
      )
    _ => fail("header must be first_row or explicit column names")
  }
  let imported = @jsontable.extract_pptx(archive, table_id~, header~)
  let query_text = if args[5] == "-" { "" } else { read_text(args[5], 65_536) }
  let query_json = if args[5] == "-" {
    Json::null()
  } else {
    @json.parse(query_text)
  }
  let (table, source_rows, matched_rows) = if args[5] == "-" {
    (imported.table, imported.source_rows, imported.table.rows.length())
  } else {
    let result = imported.table.query(@jsontable.parse_query_recipe(query_text))
    (
      result.table,
      result.source_rows.map(row => imported.source_rows[row - 1]),
      result.matched_rows,
    )
  }
  // Finish all validation/query/serialization before exclusive output creation.
  let output = match args[6] {
    "xlsx" => table.export_xlsx()
    "csv" => @utf8.encode(table.export_csv() + "\n").to_fixedarray()
    _ => @utf8.encode(table.export_json() + "\n").to_fixedarray()
  }
  write_copy(args[7], output)
  let report : Json = {
    "schema": "moonleaf.pptx-table-export.v1",
    "source_sha256": digest,
    "output_sha256": sha256(output),
    "selection": selection,
    "query": query_json,
    "format": args[6],
    "input_rows": imported.table.rows.length(),
    "matched_rows": matched_rows,
    "output_rows": table.rows.length(),
    "output_columns": table.columns,
    "table_rows": source_rows,
    "slide_number": imported.slide_number,
    "slide_part": imported.part,
    "shape_id": imported.shape_id,
    "hidden_slide": imported.hidden_slide,
    "readback_equal": true,
    "warnings": imported.warnings,
  }
  println(report.stringify())
}

///|
fn main {
  run() catch {
    error => report_error("MoonLeaf PPTX table import failed: \{Repr(error)}")
  }
}
