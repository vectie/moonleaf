///|
fn main raise {
  // Same synthetic input as docs/samples/unpivot/monthly-sales.csv.
  let source = @jsontable.parse_delimited(
    (
      #|store,region,Jan,Feb,Mar
      #|001,North,100,120,
      #|002,West,0,75,80
      #|003,North,50,,-10
      #|
    ),
  )
  let tidy = source.unpivot(
    id_columns=["store", "region"],
    value_columns=["Jan", "Feb", "Mar"],
    names_to="month",
    values_to="sales",
    drop_empty=true,
  )
  let args = @env.args()
  if args.contains("--xlsx-base64") {
    println(@base64.encode(Bytes::from_array(tidy.export_xlsx())))
  } else if args.contains("--summary") {
    let totals = tidy.summarize(group_by=["month"], measures=[
      { name: "reported_stores", operation: CountRows, },
      { name: "total", operation: Sum("sales"), },
    ])
    println(totals.export_json())
  } else {
    println(tidy.export_csv().trim_end(chars="\r\n"))
  }
}
