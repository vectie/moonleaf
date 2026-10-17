///|
extern "js" fn read_bytes(path : String, limit : Int32) -> FixedArray[Byte] =
  #|(path, limit) => { const fs = require('node:fs'); const fd = fs.openSync(path, fs.constants.O_RDONLY | fs.constants.O_NONBLOCK); try { const stat = fs.fstatSync(fd); if (!stat.isFile() || stat.size > limit) throw Error('Expected a bounded regular file'); const bytes = fs.readFileSync(fd); if (bytes.length > limit) throw Error('Input exceeds byte limit'); return Array.from(bytes); } finally { fs.closeSync(fd); } }

///|
extern "js" fn sha256(bytes : FixedArray[Byte]) -> String =
  #|bytes => require('node:crypto').createHash('sha256').update(Buffer.from(bytes)).digest('hex')

///|
extern "js" fn write_copy(path : String, bytes : FixedArray[Byte]) -> Unit =
  #|(path, bytes) => { const fs = require('node:fs'); const content = Buffer.from(bytes); fs.writeFileSync(path, content, {flag:'wx', mode:0o600}); if (!fs.readFileSync(path).equals(content)) throw Error('Dataset readback differs from serialized bytes'); }

///|
extern "js" fn report_error(message : String) -> Unit =
  #|message => { console.error(message); process.exitCode = 1; }

///|
fn definition_json(table : @xlsx.NamedTable) -> Json {
  {
    "name": table.name,
    "sheet_name": table.sheet_name,
    "table_part": table.table_part,
    "reference": table.reference,
    "import_reference": match table.import_reference {
      None => Json::null()
      Some(value) => value.to_json()
    },
    "columns": table.columns,
    "header_rows": table.header_rows,
    "totals_rows": table.totals_rows,
    "data_rows": table.data_rows,
    "calculated_columns": table.calculated_columns,
  }
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
      "usage: node xlsx-named-table.js inspect SOURCE.xlsx | export SOURCE.xlsx TABLE QUERY.json|- csv|json|xlsx FRESH_OUTPUT",
    )
  }
  let source = read_bytes(args[3], 8388608)
  let digest = sha256(source)
  let archive = @opc.open_with_policy(source, {
    ..@opc.ArchivePolicy::default(),
    max_compressed_input_bytes: 8388608,
    max_entry_compressed_bytes: 8388608,
    max_entry_uncompressed_bytes: 8388608,
    max_total_uncompressed_bytes: 16777216,
  })
  if args[2] == "inspect" {
    let report : Json = {
      "schema": "moonleaf.xlsx-named-tables.v1",
      "source_sha256": digest,
      "tables": @xlsx.named_tables(archive).map(definition_json),
      "note": "Definitions only; data cells are checked on export. Totals rows are excluded; hidden/filtered data rows are included.",
    }
    println(report.stringify())
    return
  }
  let imported = @jsontable.extract_xlsx_named_table(
    archive,
    table_name=args[4],
  )
  let query_bytes = if args[5] == "-" {
    None
  } else {
    Some(read_bytes(args[5], 65536))
  }
  let (table, source_rows, matched_rows) = match query_bytes {
    None => (imported.table, imported.source_rows, imported.table.rows.length())
    Some(bytes) => {
      let result = imported.table.query(
        @jsontable.parse_query_recipe(@utf8.decode(Bytes::from_array(bytes))),
      )
      (
        result.table,
        result.source_rows.map(row => imported.source_rows[row - 1]),
        result.matched_rows,
      )
    }
  }
  let output = match args[6] {
    "xlsx" => table.export_xlsx()
    "csv" => @utf8.encode(table.export_csv() + "\n").to_fixedarray()
    _ => @utf8.encode(table.export_json(omit_empty=true) + "\n").to_fixedarray()
  }
  write_copy(args[7], output)
  let report : Json = {
    "schema": "moonleaf.xlsx-named-table-export.v1",
    "source_sha256": digest,
    "query_sha256": match query_bytes {
      None => Json::null()
      Some(bytes) => sha256(bytes).to_json()
    },
    "definition": definition_json(imported.definition),
    "input_rows": imported.table.rows.length(),
    "matched_rows": matched_rows,
    "output_rows": table.rows.length(),
    "output_columns": table.columns,
    "worksheet_rows": source_rows,
    "warnings": imported.warnings,
    "format": args[6],
    "output_sha256": sha256(output),
    "readback_equal": true,
  }
  println(report.stringify())
}

///|
fn main {
  run() catch {
    error =>
      report_error("MoonLeaf named Excel Table import failed: \{Repr(error)}")
  }
}
