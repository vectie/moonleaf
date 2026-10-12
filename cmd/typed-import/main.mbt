///|
extern "js" fn read_utf8(path : String) -> String =
  #|path => { const fs = require('node:fs'); const fd = fs.openSync(path, fs.constants.O_RDONLY | fs.constants.O_NONBLOCK); try { const stat = fs.fstatSync(fd); if (!stat.isFile() || stat.size > 8388608) throw Error('Expected a regular file no larger than 8 MiB'); const bytes = fs.readFileSync(fd); if (bytes.length > 8388608) throw Error('File exceeds 8 MiB'); return new TextDecoder('utf-8', {fatal: true}).decode(bytes); } finally { fs.closeSync(fd); } }

///|
extern "js" fn write_bytes(bytes : FixedArray[Byte]) -> Unit =
  #|bytes => require('node:fs').writeFileSync(1, Buffer.from(bytes))

///|
extern "js" fn report_error(message : String) -> Unit =
  #|message => { console.error(message); process.exitCode = 1; }

///|
fn run() -> Unit raise {
  let args = @env.args()
  guard args.length() == 6 &&
    ["csv", "tsv"].contains(args[2]) &&
    args[3] != "-" &&
    args[4] != "-" &&
    ["csv", "json", "xlsx"].contains(args[5]) else {
    fail("usage: node typed-import.js csv|tsv SOURCE SCHEMA csv|json|xlsx")
  }
  let schema = @jsontable.parse_delimited_schema(read_utf8(args[4]))
  let table = @jsontable.parse_typed_delimited(
    read_utf8(args[3]),
    schema,
    delimiter=if args[2] == "tsv" { '\t' } else { ',' },
  )
  // Validate and serialize fully before writing any dataset bytes to stdout.
  match args[5] {
    "xlsx" => write_bytes(table.export_xlsx())
    "csv" => println(table.export_csv().trim_end(chars="\r\n"))
    _ => println(table.export_json(omit_empty=true))
  }
}

///|
fn main {
  run() catch {
    error => report_error("MoonLeaf typed import failed: \{Repr(error)}")
  }
}
