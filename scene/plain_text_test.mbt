///|
test "plain text keeps paragraph, heading, list and table content" {
  let style = @scene.TextStyle::plain()
  let document : @scene.TextDocument = {
    blocks: [
      @scene.Heading(1, [{ text: "研究", style, }]),
      @scene.Paragraph([{ text: "收入", style, }, { text: "增长", style, }]),
      @scene.ListItem(level=0, ordered=false, [{ text: "订单", style, }]),
      @scene.Table([["甲", "乙"], ["丙", "丁"]]),
    ],
    warnings: [],
  }
  assert_eq(
    document.plain_text(),
    "研究\n收入增长\n订单\n甲\n乙\n丙\n丁",
  )
}
