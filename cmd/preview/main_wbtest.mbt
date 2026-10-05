///|
test "replace all text preserves Unicode and ignores ASCII letter case" {
  assert_eq(
    replace_visible_text("Alpha alpha，阿尔法 Alpha", "ALPHA", "研究"),
    "研究 研究，阿尔法 研究",
  )
  assert_eq(
    replace_visible_text("公司公告 公司", "公司", "企业"),
    "企业公告 企业",
  )
  assert_eq(replace_visible_text("untouched", "missing", "new"), "untouched")
}
