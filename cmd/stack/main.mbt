///|
extern "js" fn read_utf8(path : String) -> String =
  #|path => new TextDecoder('utf-8', {fatal: true}).decode(require('node:fs').readFileSync(path === '-' ? 0 : path))

///|
extern "js" fn write_bytes(bytes : FixedArray[Byte]) -> Unit = "bytes => require('node:fs').writeFileSync(1, Buffer.from(bytes))"

///|
extern "js" fn report_error(message : String) -> Unit = "message => { console.error(message); process.exitCode = 1; }"

///|
fn run() -> Unit raise {
  let args = @env.args()
  guard args.length() >= 7 &&
    args.length() <= 196 &&
    (args.length() - 4) % 3 == 0 &&
    ["strict", "union"].contains(args[2]) &&
    ["csv", "json", "xlsx"].contains(args[3]) else {
    fail(
      "usage: node stack.js strict|union csv|json|xlsx LABEL FORMAT PATH [LABEL FORMAT PATH ...]",
    )
  }
  let tables : Array[@jsontable.Table] = []
  let sources : Array[String] = []
  for i = 4; i < args.length(); i = i + 3 {
    let format = args[i + 1]
    if !["csv", "tsv", "json", "jsonl"].contains(format) || args[i + 2] == "-" {
      fail("Expected csv, tsv, json or jsonl and an explicit file path")
    }
    let input = read_utf8(args[i + 2])
    let table = match format {
      "csv" => @jsontable.parse_delimited(input)
      "tsv" => @jsontable.parse_delimited(input, delimiter='\t')
      "jsonl" => @jsontable.parse(input, jsonl=true)
      _ => @jsontable.parse(input)
    }
    tables.push(table)
    sources.push(args[i])
  }
  let mode = if args[2] == "strict" {
    @jsontable.StrictHeaders
  } else {
    @jsontable.UnionHeaders
  }
  let output = @jsontable.stack(tables, sources~, mode~)
  match args[3] {
    "xlsx" => write_bytes(output.export_xlsx())
    "csv" => println(output.export_csv().trim_end(chars="\r\n"))
    _ => println(output.export_json(omit_empty=true))
  }
}

///|
fn main {
  run() catch {
    error => report_error("MoonLeaf stack failed: \{Repr(error)}")
  }
}
