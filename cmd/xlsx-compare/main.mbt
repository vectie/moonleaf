///|
extern "js" fn read_bytes(path : String) -> FixedArray[Byte] =
  #|path => { const fs = require('node:fs'); const fd = fs.openSync(path, fs.constants.O_RDONLY | fs.constants.O_NONBLOCK); try { const stat = fs.fstatSync(fd); if (!stat.isFile() || stat.size > 8388608) throw Error('Expected a regular XLSX file of at most 8 MiB'); const bytes = fs.readFileSync(fd); if (bytes.length > 8388608) throw Error('Input exceeds 8 MiB'); return Array.from(bytes); } finally { fs.closeSync(fd); } }

///|
extern "js" fn sha256(bytes : FixedArray[Byte]) -> String =
  #|bytes => require('node:crypto').createHash('sha256').update(Buffer.from(bytes)).digest('hex')

///|
extern "js" fn report_error(message : String) -> Unit =
  #|message => { console.error(message); process.exitCode = 1; }

///|
fn run() -> Unit raise {
  let args = @env.args()
  guard args.length() == 4 || args.length() == 5 else {
    fail(
      "usage: node xlsx-compare.js ORIGINAL.xlsx CLIENT_COPY.xlsx [json|text]",
    )
  }
  let format = if args.length() == 5 { args[4] } else { "json" }
  if format != "json" && format != "text" {
    fail("format must be json or text")
  }
  let before = read_bytes(args[2])
  let after = read_bytes(args[3])
  let policy : @opc.ArchivePolicy = {
    ..@opc.ArchivePolicy::default(),
    max_compressed_input_bytes: 8_388_608,
    max_entry_compressed_bytes: 8_388_608,
    max_entry_uncompressed_bytes: 8_388_608,
    max_total_uncompressed_bytes: 16_777_216,
  }
  let comparison = @xlsx.compare_workbooks(
    @opc.open_with_policy(before, policy),
    @opc.open_with_policy(after, policy),
  )
  let report : Json = {
    "schema": "moonleaf.workbook-comparison.v1",
    "original_sha256": sha256(before),
    "copy_sha256": sha256(after),
    "identical_bytes": before == after,
    "supported_content_changed": !comparison.sheets.is_empty() ||
    comparison.date_system_changed,
    "comparison": comparison.to_json(),
  }
  if format == "text" {
    println(
      text_report(comparison, sha256(before), sha256(after), before == after),
    )
  } else {
    println(report.stringify())
  }
}

///|
fn main {
  run() catch {
    error => report_error("MoonLeaf workbook comparison failed: \{Repr(error)}")
  }
}
