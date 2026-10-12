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
  guard args.length() == 7 &&
    ["csv", "tsv", "json", "jsonl"].contains(args[2]) &&
    args[3] != "-" &&
    args[4] != "-" &&
    ["copy", "report"].contains(args[5]) &&
    ["csv", "json", "xlsx"].contains(args[6]) else {
    fail(
      "usage: node correct.js csv|tsv|json|jsonl SOURCE RECIPE copy|report csv|json|xlsx",
    )
  }
  let recipe = @jsontable.parse_correction_recipe(read_utf8(args[4]))
  let input = read_utf8(args[3])
  if input.length() > 4_000_000 {
    fail("Input exceeds 4000000 UTF-16 units")
  }
  let table = match args[2] {
    "csv" => @jsontable.parse_delimited(input)
    "tsv" => @jsontable.parse_delimited(input, delimiter='\t')
    "jsonl" => @jsontable.parse(input, jsonl=true)
    _ => @jsontable.parse(input)
  }
  let result = table.correct(recipe)
  let output = if args[5] == "copy" { result.table } else { result.report }
  // Complete all validation and serialization before writing dataset bytes.
  match args[6] {
    "xlsx" => write_bytes(output.export_xlsx())
    "csv" => println(output.export_csv().trim_end(chars="\r\n"))
    _ => println(output.export_json(omit_empty=true))
  }
}

///|
fn main {
  run() catch {
    error => report_error("MoonLeaf correction failed: \{Repr(error)}")
  }
}
