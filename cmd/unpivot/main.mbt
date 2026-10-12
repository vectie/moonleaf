///|
extern "js" fn read_utf8(path : String) -> String =
  #|path => new TextDecoder('utf-8', {fatal: true}).decode(require('node:fs').readFileSync(path === '-' ? 0 : path))

///|
extern "js" fn write_bytes(bytes : FixedArray[Byte]) -> Unit = "bytes => require('node:fs').writeFileSync(1, Buffer.from(bytes))"

///|
extern "js" fn report_error(message : String) -> Unit = "message => { console.error(message); process.exitCode = 1; }"

///|
fn column_names(value : Json) -> Array[String] raise {
  guard value is Array(items) else { fail("Expected an array of column names") }
  items.map(item => {
    guard item is String(name) else { fail("Column names must be strings") }
    name
  })
}

///|
fn parse_spec(
  text : String,
) -> (Array[String], Array[String], String, String, Bool) raise {
  let spec = @json.parse(text)
  guard spec is Object(fields) else { fail("Expected an unpivot spec object") }
  for key, _ in fields {
    if !["id_columns", "value_columns", "names_to", "values_to", "drop_empty"].contains(
        key,
      ) {
      fail("Unknown unpivot spec field: " + key)
    }
  }
  guard fields.get("id_columns") is Some(ids) &&
    fields.get("value_columns") is Some(values) else {
    fail("Unpivot spec needs id_columns and value_columns arrays")
  }
  let names_to = match fields.get("names_to") {
    None => "variable"
    Some(String(name)) => name
    _ => fail("names_to must be a string")
  }
  let values_to = match fields.get("values_to") {
    None => "value"
    Some(String(name)) => name
    _ => fail("values_to must be a string")
  }
  let drop_empty = match fields.get("drop_empty") {
    None | Some(False) => false
    Some(True) => true
    _ => fail("drop_empty must be a boolean")
  }
  (column_names(ids), column_names(values), names_to, values_to, drop_empty)
}

///|
fn run() -> Unit raise {
  let args = @env.args()
  guard args.length() == 5 &&
    ["csv", "tsv", "json", "jsonl"].contains(args[2]) &&
    ["csv", "json", "xlsx"].contains(args[4]) else {
    fail(
      "usage: node unpivot.js csv|tsv|json|jsonl SPEC.json csv|json|xlsx < INPUT > COPY",
    )
  }
  let (id_columns, value_columns, names_to, values_to, drop_empty) = parse_spec(
    read_utf8(args[3]),
  )
  let input = read_utf8("-")
  let table = match args[2] {
    "csv" => @jsontable.parse_delimited(input)
    "tsv" => @jsontable.parse_delimited(input, delimiter='\t')
    "jsonl" => @jsontable.parse(input, jsonl=true)
    _ => @jsontable.parse(input)
  }
  let output = table.unpivot(
    id_columns~,
    value_columns~,
    names_to~,
    values_to~,
    drop_empty~,
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
    error => report_error("MoonLeaf unpivot failed: \{Repr(error)}")
  }
}
