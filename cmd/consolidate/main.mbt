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
  guard args.length() >= 10 &&
    args.length() <= 199 &&
    (args.length() - 7) % 3 == 0 &&
    ["strict", "union"].contains(args[2]) &&
    ["first", "last"].contains(args[3]) &&
    ["kept", "report"].contains(args[4]) &&
    ["csv", "json", "xlsx"].contains(args[5]) else {
    fail(
      "usage: node consolidate.js strict|union first|last kept|report csv|json|xlsx '[\"key\",...]' LABEL FORMAT PATH [LABEL FORMAT PATH ...]",
    )
  }
  if args[6].length() > 65536 {
    fail("Key specification exceeds 65536 code units")
  }
  guard @json.parse(args[6]) is Array(items) && items.length() <= 32 else {
    fail("Keys must be a JSON array of 1–32 column names")
  }
  let keys : Array[String] = []
  for item in items {
    guard item is String(name) else { fail("Key column names must be strings") }
    keys.push(name)
  }
  let tables : Array[@jsontable.Table] = []
  let sources : Array[String] = []
  let mut total_units = 0
  for i = 7; i < args.length(); i = i + 3 {
    let format = args[i + 1]
    if !["csv", "tsv", "json", "jsonl"].contains(format) || args[i + 2] == "-" {
      fail("Expected csv, tsv, json or jsonl and an explicit file path")
    }
    let input = read_utf8(args[i + 2])
    total_units += input.length()
    if total_units > 8_388_608 {
      fail("Combined input exceeds 8388608 code units")
    }
    tables.push(
      match format {
        "csv" => @jsontable.parse_delimited(input)
        "tsv" => @jsontable.parse_delimited(input, delimiter='\t')
        "jsonl" => @jsontable.parse(input, jsonl=true)
        _ => @jsontable.parse(input)
      },
    )
    sources.push(args[i])
  }
  let stacked = @jsontable.stack(
    tables,
    sources~,
    mode=if args[2] == "strict" {
      @jsontable.StrictHeaders
    } else {
      @jsontable.UnionHeaders
    },
  )
  let result = stacked.consolidate(
    key_columns=keys,
    retention=if args[3] == "first" {
      @jsontable.KeepFirst
    } else {
      @jsontable.KeepLast
    },
  )
  let output = if args[4] == "kept" { result.kept } else { result.report }
  // No dataset bytes are emitted before all inputs and both tables are validated.
  match args[5] {
    "xlsx" => write_bytes(output.export_xlsx())
    "csv" => println(output.export_csv().trim_end(chars="\r\n"))
    _ => println(output.export_json(omit_empty=true))
  }
}

///|
fn main {
  run() catch {
    error => report_error("MoonLeaf consolidate failed: \{Repr(error)}")
  }
}
