///|
extern "js" fn read_stdin() -> String = "() => require('node:fs').readFileSync(0, 'utf8')"

///|
extern "js" fn read_spec(path : String) -> String = "(path) => require('node:fs').readFileSync(path, 'utf8')"

///|
extern "js" fn report_error(message : String) -> Unit = "(message) => { console.error(message); process.exitCode = 1; }"

///|
fn parse_spec(
  text : String,
) -> (Array[String], Array[@jsontable.SummaryMeasure]) raise {
  let spec = @json.parse(text)
  guard spec is { "group_by": Array(keys), "measures": Array(items), .. } else {
    fail("Summary spec needs group_by and measures arrays")
  }
  let columns : Array[String] = []
  for key in keys {
    guard key is String(column) else {
      fail("group_by entries must be column names")
    }
    columns.push(column)
  }
  let measures : Array[@jsontable.SummaryMeasure] = []
  for item in items {
    guard item is { "name": String(name), "op": String(op), .. } else {
      fail("Each measure needs name and op")
    }
    let operation = if op == "count" {
      @jsontable.CountRows
    } else {
      guard item is { "column": String(column), .. } else {
        fail("sum and mean measures need a column")
      }
      match op {
        "sum" => Sum(column)
        "mean" => Mean(column)
        _ => fail("Unknown measure op: " + op)
      }
    }
    measures.push({ name, operation, })
  }
  (columns, measures)
}

///|
fn run() -> Unit raise {
  let args = @env.args()
  guard args.length() == 5 else {
    fail(
      "usage: node summarize.js csv|tsv|json|jsonl SPEC.json csv|json < INPUT",
    )
  }
  if !["csv", "tsv", "json", "jsonl"].contains(args[2]) ||
    !["csv", "json"].contains(args[4]) {
    fail("Expected input csv|tsv|json|jsonl and output csv|json")
  }
  let (group_by, measures) = parse_spec(read_spec(args[3]))
  let input = read_stdin()
  let table = match args[2] {
    "csv" => @jsontable.parse_delimited(input)
    "tsv" => @jsontable.parse_delimited(input, delimiter='\t')
    "jsonl" => @jsontable.parse(input, jsonl=true)
    _ => @jsontable.parse(input)
  }
  let summary = table.summarize(group_by~, measures~)
  // Produce nothing on stdout until the entire result has been computed.
  println(
    if args[4] == "json" {
      summary.export_json()
    } else {
      summary.export_csv()
    },
  )
}

///|
fn main {
  run() catch {
    error => report_error("MoonLeaf summary failed: \{Repr(error)}")
  }
}
