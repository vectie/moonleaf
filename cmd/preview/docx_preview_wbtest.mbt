///|
test "DOCX preview JSON retains table geometry and merge state" {
  let archive : @opc.Package = { parts: [], }
  let archive = archive.replace_text(
    "word/document.xml",
    (
      #|<w:document xmlns:w="urn:w"><w:body><w:tbl>
      #|<w:tblGrid><w:gridCol w:w="2400"/></w:tblGrid>
      #|<w:tr><w:trPr><w:trHeight w:val="781" w:hRule="atLeast"/></w:trPr>
      #|<w:tc><w:tcPr><w:tcW w:w="2400"/><w:vMerge w:val="restart"/><w:tcMar><w:top w:w="60"/><w:right w:w="90"/><w:bottom w:w="30"/><w:left w:w="120"/></w:tcMar><w:vAlign w:val="center"/></w:tcPr><w:p><w:r><w:t>第一行</w:t></w:r></w:p></w:tc></w:tr>
      #|<w:tr><w:tc><w:tcPr><w:vMerge/></w:tcPr><w:p><w:r><w:t>第二行</w:t></w:r></w:p></w:tc></w:tr>
      #|</w:tbl></w:body></w:document>
    ),
  )
  let document = @docx.preview_document(archive)
  guard document.blocks is [FlowTable(table)] else { fail("expected a table") }
  let json = docx_table_json(table, Ref(0))
  guard json is { "rows": Array(rows), .. } && rows.length() == 2 else {
    fail("expected two JSON rows")
  }
  guard rows[0]
    is {
      "height_twips": first_height,
      "height_rule": String("atLeast"),
      "cells": Array(first_cells),
      ..
    } else {
    fail("first row lost its height rule")
  }
  assert_true(first_height == @json.to_json(781))
  guard first_cells[0]
    is {
      "vertical_merge": String("restart"),
      "margin_top_twips": top,
      "margin_right_twips": right,
      "margin_bottom_twips": bottom,
      "margin_left_twips": left,
      ..
    } else {
    fail("first cell lost merge state or margins")
  }
  assert_true(top == @json.to_json(60))
  assert_true(right == @json.to_json(90))
  assert_true(bottom == @json.to_json(30))
  assert_true(left == @json.to_json(120))
  guard rows[1] is { "height_rule": Null, "cells": Array(last_cells), .. } else {
    fail("absent row height rule should be null")
  }
  assert_true(last_cells[0] is { "vertical_merge": String("continue"), .. })
  assert_true(last_cells[0] is { "margin_left_twips": Null, .. })
}
