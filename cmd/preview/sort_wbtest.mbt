///|
test "CSV sort keeps header and complete quoted rows together" {
  let table = @csv.parse(
    "名称,数值,备注\r\n甲,12,\"A,B\"\r\n乙,2,小\r\n丙,10,中",
  )
  let (sorted, count) = sorted_delimited(table, 2, false, true)
  assert_eq(count, 3)
  assert_eq(sorted.rows[0], ["名称", "数值", "备注"])
  assert_eq(sorted.rows[1], ["乙", "2", "小"])
  assert_eq(sorted.rows[2], ["丙", "10", "中"])
  assert_eq(sorted.rows[3], ["甲", "12", "A,B"])
  assert_eq(@csv.parse(sorted.serialize()).rows, sorted.rows)
  assert_eq(table.rows[1], ["甲", "12", "A,B"])
  let (descending, _) = sorted_delimited(table, 2, true, true)
  assert_eq(descending.rows[1][0], "甲")
}

///|
test "CSV sort can include the first row and keeps blanks at the end" {
  let table = @csv.parse("12,甲\n,空\n2,乙")
  let (sorted, count) = sorted_delimited(table, 1, false, false)
  assert_eq(count, 3)
  assert_eq(sorted.rows.map(row => row[1]), ["乙", "甲", "空"])
  let (descending, _) = sorted_delimited(table, 1, true, false)
  assert_eq(descending.rows.map(row => row[1]), ["甲", "乙", "空"])
}
