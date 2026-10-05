///|
test "create XLSX roundtrips Unicode, numbers, literal formulas and header style" {
  let bytes = @xlsx.create(
    [
      [@scene.Text("标题"), @scene.Text("序号")],
      [@scene.Text("债券 & 公司"), @scene.Number("12")],
      [@scene.Text("=1+1"), @scene.Text("换行\n测试")],
    ],
    sheet_name="研究证据",
  )
  let workbook = @xlsx.read(@opc.open(bytes))
  assert_eq(workbook.sheets.length(), 1)
  assert_eq(workbook.sheets[0].name, "研究证据")
  assert_eq(workbook.sheets[0].cells[2].value, @scene.Text("债券 & 公司"))
  assert_eq(workbook.sheets[0].cells[3].value, @scene.Number("12"))
  assert_eq(workbook.sheets[0].cells[4].value, @scene.Text("=1+1"))
  assert_eq(workbook.sheets[0].cells[5].value, @scene.Text("换行\n测试"))
  assert_eq(workbook.sheets[0].cells[0].style_id, Some(1))
}
