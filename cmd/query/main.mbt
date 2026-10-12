///|
extern "js" fn read_utf8(path : String) -> String =
  #|path => { const fs = require('node:fs'); const data = fs.readFileSync(path); if(data.length > 8*1024*1024) throw new Error('Input exceeds 8 MiB'); return new TextDecoder('utf-8', {fatal:true}).decode(data); }

///|
extern "js" fn write_bytes(bytes : FixedArray[Byte]) -> Unit = "bytes => require('node:fs').writeFileSync(1, Buffer.from(bytes))"

///|
extern "js" fn report_error(message : String) -> Unit = "message => { console.error(message); process.exitCode = 1; }"

///|
fn run() -> Unit raise {
  let args = @env.args()
  guard args.length() == 6 &&
    ["csv", "tsv", "json", "jsonl"].contains(args[2]) &&
    ["csv", "json", "xlsx"].contains(args[5]) &&
    args[3] != "-" &&
    args[4] != "-" else {
    fail(
      "usage: node query.js csv|tsv|json|jsonl INPUT_PATH RECIPE_PATH csv|json|xlsx",
    )
  }
  let recipe = @jsontable.parse_query_recipe(read_utf8(args[4]))
  let text = read_utf8(args[3])
  let input = match args[2] {
    "csv" => @jsontable.parse_delimited(text)
    "tsv" => @jsontable.parse_delimited(text, delimiter='\t')
    "jsonl" => @jsontable.parse(text, jsonl=true)
    _ => @jsontable.parse(text)
  }
  let output = input.query(recipe).table
  match args[5] {
    "xlsx" => write_bytes(output.export_xlsx())
    "csv" => println(output.export_csv().trim_end(chars="\r\n"))
    _ => println(output.export_json(omit_empty=true))
  }
}

///|
fn main {
  run() catch {
    error => report_error("MoonLeaf query failed: \{Repr(error)}")
  }
}
