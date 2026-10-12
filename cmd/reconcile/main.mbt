///|
extern "js" fn read_utf8(path : String) -> String =
  #|path => new TextDecoder('utf-8', {fatal: true}).decode(require('node:fs').readFileSync(path))

///|
extern "js" fn write_bytes(bytes : FixedArray[Byte]) -> Unit = "bytes => require('node:fs').writeFileSync(1, Buffer.from(bytes))"

///|
extern "js" fn report_error(message : String) -> Unit = "message => { console.error(message); process.exitCode = 1; }"

///|
fn read_table(format : String, path : String) -> @jsontable.Table raise {
  if path == "-" {
    fail("An explicit input file path is required")
  }
  if !["csv", "tsv", "json", "jsonl"].contains(format) {
    fail("Expected csv, tsv, json or jsonl input format")
  }
  let input = read_utf8(path)
  match format {
    "csv" => @jsontable.parse_delimited(input)
    "tsv" => @jsontable.parse_delimited(input, delimiter='\t')
    "jsonl" => @jsontable.parse(input, jsonl=true)
    _ => @jsontable.parse(input)
  }
}

///|
fn run() -> Unit raise {
  let args = @env.args()
  guard args.length() == 9 &&
    ["all", "changes"].contains(args[2]) &&
    ["csv", "json", "xlsx"].contains(args[3]) else {
    fail(
      "usage: node reconcile.js all|changes csv|json|xlsx '[\"key\",...]' BEFORE_FORMAT BEFORE_PATH AFTER_FORMAT AFTER_PATH",
    )
  }
  let keys : Array[String] = []
  guard @json.parse(args[4]) is Array(items) else {
    fail("Keys must be a JSON array of column names")
  }
  for item in items {
    guard item is String(name) else { fail("Key column names must be strings") }
    keys.push(name)
  }
  let before = read_table(args[5], args[6])
  let after = read_table(args[7], args[8])
  let output = before.reconcile(
    after,
    key_columns=keys,
    include_unchanged=args[2] == "all",
  )
  // Complete validation and serialization before sending any dataset bytes.
  match args[3] {
    "xlsx" => write_bytes(output.export_xlsx())
    "csv" => println(output.export_csv().trim_end(chars="\r\n"))
    _ => println(output.export_json(omit_empty=true))
  }
}

///|
fn main {
  run() catch {
    error => report_error("MoonLeaf reconcile failed: \{Repr(error)}")
  }
}
