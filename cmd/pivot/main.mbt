///|
extern "js" fn read_utf8(path : String) -> String =
  #|path => new TextDecoder('utf-8', {fatal: true}).decode(require('node:fs').readFileSync(path === '-' ? 0 : path))

///|
extern "js" fn write_bytes(bytes : FixedArray[Byte]) -> Unit = "bytes => require('node:fs').writeFileSync(1, Buffer.from(bytes))"

///|
extern "js" fn report_error(message : String) -> Unit = "message => { console.error(message); process.exitCode = 1; }"

///|
fn parse_spec(
  text : String,
) -> (Array[String], String, String, @jsontable.PivotDuplicates, String) raise {
  let spec = @json.parse(text)
  guard spec is Object(fields) else { fail("Expected a pivot spec object") }
  for key, _ in fields {
    if !["id_columns", "key_column", "value_column", "duplicates", "prefix"].contains(
        key,
      ) {
      fail("Unknown pivot spec field: " + key)
    }
  }
  guard fields.get("id_columns") is Some(Array(ids)) &&
    fields.get("key_column") is Some(String(key_column)) &&
    fields.get("value_column") is Some(String(value_column)) else {
    fail(
      "Pivot spec needs id_columns array, key_column and value_column strings",
    )
  }
  let identifiers = ids.map(item => {
    guard item is String(name) else {
      fail("Identifier column names must be strings")
    }
    name
  })
  let duplicates = match fields.get("duplicates") {
    None | Some(String("reject")) => @jsontable.Reject
    Some(String("first")) => First
    Some(String("last")) => Last
    _ => fail("duplicates must be reject, first or last")
  }
  let prefix = match fields.get("prefix") {
    None => ""
    Some(String(value)) => value
    _ => fail("prefix must be a string")
  }
  (identifiers, key_column, value_column, duplicates, prefix)
}

///|
fn run() -> Unit raise {
  let args = @env.args()
  guard args.length() == 5 &&
    ["csv", "tsv", "json", "jsonl"].contains(args[2]) &&
    ["csv", "json", "xlsx"].contains(args[4]) else {
    fail(
      "usage: node pivot.js csv|tsv|json|jsonl SPEC.json csv|json|xlsx < INPUT > COPY",
    )
  }
  let (id_columns, key_column, value_column, duplicates, prefix) = parse_spec(
    read_utf8(args[3]),
  )
  let input = read_utf8("-")
  let table = match args[2] {
    "csv" => @jsontable.parse_delimited(input)
    "tsv" => @jsontable.parse_delimited(input, delimiter='\t')
    "jsonl" => @jsontable.parse(input, jsonl=true)
    _ => @jsontable.parse(input)
  }
  let output = table.pivot(
    id_columns~,
    key_column~,
    value_column~,
    duplicates~,
    prefix~,
  )
  match args[4] {
    "xlsx" => write_bytes(output.export_xlsx())
    "csv" => println(output.export_csv().trim_end(chars="\r\n"))
    _ => println(output.export_json(omit_empty=true))
  }
}

///|
fn main {
  run() catch {
    error => report_error("MoonLeaf pivot failed: \{Repr(error)}")
  }
}
