///|
fn edit_ops_test_package() -> @opc.Package {
  let styles = "<w:styles xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\"><w:style w:type=\"paragraph\" w:styleId=\"Heading1\"><w:name w:val=\"heading 1\"/><w:pPr><w:outlineLvl w:val=\"0\"/></w:pPr></w:style><w:style w:type=\"paragraph\" w:styleId=\"Heading2\"><w:name w:val=\"heading 2\"/><w:pPr><w:outlineLvl w:val=\"1\"/></w:pPr></w:style></w:styles>"
  let document = "<w:document xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\"><w:body><w:p><w:pPr><w:pStyle w:val=\"Heading1\"/></w:pPr><w:r><w:t>Introduction</w:t></w:r></w:p><w:p><w:r><w:t>Hello world today</w:t></w:r></w:p><w:p><w:pPr><w:pStyle w:val=\"Heading2\"/></w:pPr><w:r><w:t>Details</w:t></w:r></w:p><w:p><w:r><w:t>Detail one</w:t></w:r></w:p><w:p><w:pPr><w:pStyle w:val=\"Heading1\"/></w:pPr><w:r><w:t>Conclusion</w:t></w:r></w:p><w:p><w:r><w:t>Final note</w:t></w:r></w:p></w:body></w:document>"
  let content_types = "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"xml\" ContentType=\"application/xml\"/></Types>"
  let pkg : @opc.Package = { parts: [], }
  pkg
  .replace_text("[Content_Types].xml", content_types)
  .replace_text("word/styles.xml", styles)
  .replace_text("word/document.xml", document)
}

///|
test "document_outline lists headings and counts paragraphs and tables" {
  let pkg = edit_ops_test_package()
  let outline = @docx.document_outline(pkg)
  guard outline
    is {
      "paragraphs": Number(6.0, ..),
      "tables": Number(0.0, ..),
      "headings": Array(headings),
      ..
    } else {
    fail("unexpected outline json: " + outline.stringify())
  }
  assert_eq(headings.length(), 3)
  assert_true(
    headings[0]
    is {
      "paragraph_index": Number(0.0, ..),
      "level": Number(1.0, ..),
      "text": String("Introduction"),
      ..
    },
  )
  assert_true(
    headings[1]
    is {
      "paragraph_index": Number(2.0, ..),
      "level": Number(2.0, ..),
      "text": String("Details"),
      ..
    },
  )
  assert_true(
    headings[2]
    is {
      "paragraph_index": Number(4.0, ..),
      "level": Number(1.0, ..),
      "text": String("Conclusion"),
      ..
    },
  )
}

///|
test "apply_edit_ops handles paragraph replace insert delete and extended styles" {
  let pkg = edit_ops_test_package()
  let (updated, report) = @docx.apply_edit_ops(pkg, {
    "ops": [
      {
        "op": "replace",
        "target": { "paragraph_index": 1 },
        "text": "Updated body",
        "style": {
          "bold": true,
          "strike": true,
          "highlight": "yellow",
          "underline_style": "double",
        },
      },
      {
        "op": "insert_after",
        "target": { "paragraph_index": 0 },
        "paragraphs": ["Inserted after heading"],
      },
      {
        "op": "insert_before",
        "target": { "paragraph_index": 2 },
        "paragraphs": ["Inserted before updated"],
      },
      {
        "op": "format",
        "target": { "paragraph_index": 2 },
        "style": { "shade": "E6F4EA", "paragraph_shade": "F8FAFC" },
      },
      { "op": "delete", "target": { "paragraph_index": 1 } },
    ],
  })
  assert_true(report is { "applied": Number(5.0, ..), .. })
  let xml = updated.text("word/document.xml")
  assert_true(xml.contains(">Inserted before updated</w:t>"))
  assert_true(xml.contains(">Updated body</w:t>"))
  assert_false(xml.contains("Inserted after heading"))
  assert_true(xml.contains("<w:strike w:val=\"1\"/>"))
  assert_true(xml.contains("<w:highlight w:val=\"yellow\"/>"))
  assert_true(xml.contains("<w:u w:val=\"double\"/>"))
  assert_true(xml.contains("w:fill=\"E6F4EA\""))
  assert_true(xml.contains("w:fill=\"F8FAFC\""))
}

///|
test "apply_edit_ops supports mid-run format_range replace_range and comments" {
  let pkg = edit_ops_test_package()
  let (updated, _) = @docx.apply_edit_ops(pkg, {
    "author": "Reviewer",
    "date": "2026-11-26T00:00:00Z",
    "ops": [
      {
        "op": "format_range",
        "target": { "paragraph_index": 1 },
        "range": { "start": 6, "end": 11 },
        "style": { "highlight": "cyan", "bold": true },
      },
      {
        "op": "replace_range",
        "target": { "paragraph_index": 1 },
        "range": { "start": 6, "end": 11 },
        "text": "MoonLeaf",
      },
      {
        "op": "comment",
        "target": { "paragraph_index": 1 },
        "range": { "start": 6, "end": 14 },
        "text": "Check brand capitalization",
      },
    ],
  })
  let xml = updated.text("word/document.xml")
  assert_true(xml.contains(">Hello </w:t>"))
  assert_true(xml.contains(">MoonLeaf</w:t>"))
  assert_true(xml.contains("> today</w:t>"))
  assert_true(xml.contains("<w:commentRangeStart w:id=\"0\"/>"))
  assert_true(xml.contains("<w:commentRangeEnd w:id=\"0\"/>"))
  assert_true(xml.contains("<w:commentReference w:id=\"0\"/>"))
  assert_true(updated.has_part("word/comments.xml"))
  assert_true(
    updated
    .text("word/_rels/document.xml.rels")
    .contains("relationships/comments"),
  )
  assert_true(updated.text("[Content_Types].xml").contains("comments+xml"))
  let comments = @docx.list_comments(updated)
  assert_eq(comments.length(), 1)
  assert_true(
    comments[0]
    is {
      "id": Number(0.0, ..),
      "author": String("Reviewer"),
      "text": String("Check brand capitalization"),
      "paragraph_index": Number(1.0, ..),
      ..
    },
  )
}

///|
test "apply_edit_ops supports section operations" {
  let pkg = edit_ops_test_package()
  let (with_insert, _) = @docx.apply_edit_ops(pkg, {
    "ops": [
      {
        "op": "insert_in_section",
        "section": { "heading": "Details" },
        "position": "end",
        "paragraphs": ["Detail two"],
      },
      {
        "op": "insert_section_after",
        "section": { "heading": "Conclusion" },
        "heading_text": "Appendix",
        "heading_level": 1,
        "paragraphs": ["Appendix A"],
      },
    ],
  })
  let xml1 = with_insert.text("word/document.xml")
  assert_true(xml1.contains(">Detail two</w:t>"))
  assert_true(xml1.contains(">Appendix</w:t>"))
  assert_true(xml1.contains(">Appendix A</w:t>"))

  let (replaced, _) = @docx.apply_edit_ops(with_insert, {
    "ops": [
      {
        "op": "replace_section",
        "section": { "heading": "Introduction" },
        "include_subsections": true,
        "paragraphs": ["Fresh intro"],
      },
      { "op": "delete_section", "section": { "heading": "Appendix" } },
    ],
  })
  let xml2 = replaced.text("word/document.xml")
  assert_true(xml2.contains(">Fresh intro</w:t>"))
  assert_false(xml2.contains("Detail one"))
  assert_false(xml2.contains("Appendix"))
}

///|
test "apply_edit_ops is atomic on failure and guards tables in sections" {
  let pkg : @opc.Package = { parts: [], }
  let doc = "<w:document xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\"><w:body><w:p><w:pPr><w:pStyle w:val=\"Heading1\"/></w:pPr><w:r><w:t>Data</w:t></w:r></w:p><w:tbl><w:tr><w:tc><w:p><w:r><w:t>Cell</w:t></w:r></w:p></w:tc></w:tr></w:tbl><w:p><w:r><w:t>After</w:t></w:r></w:p></w:body></w:document>"
  let pkg = pkg.replace_text("word/document.xml", doc)
  let mut failed = false
  try
    @docx.apply_edit_ops(pkg, {
      "ops": [
        {
          "op": "replace",
          "target": { "paragraph_index": 1 },
          "text": "Changed",
        },
        {
          "op": "replace_section",
          "section": { "heading": "Data" },
          "paragraphs": ["Wiped"],
        },
      ],
    })
  catch {
    _ => failed = true
  } noraise {
    _ => ()
  }
  assert_true(failed)
  assert_true(pkg.text("word/document.xml").contains("<w:t>After</w:t>"))
}
