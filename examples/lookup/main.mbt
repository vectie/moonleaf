///|
fn main raise {
  let orders = @jsontable.parse(
    (
      #|[{"order":"SO-104","customer":"001","amount":1250.5},
      #| {"order":"SO-105","customer":"002","amount":240},
      #| {"order":"SO-106","customer":"unknown","amount":75}]
    ),
  )
  let customers = @jsontable.parse_delimited(
    (
      #|id,name,region
      #|002,"Acme, Inc",West
      #|001,東京商店,East
      #|
    ),
  )
  let prepared = orders.lookup(
    customers,
    source_key="customer",
    lookup_key="id",
    columns=["name", "region"],
    prefix="customer.",
  )
  if @env.args().contains("--xlsx-base64") {
    println(@base64.encode(Bytes::from_array(prepared.table.export_xlsx())))
  } else {
    println(prepared.table.export_csv().trim_end(chars="\r\n"))
  }
}
