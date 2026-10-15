///|
fn target_package(body : String) -> @opc.Package {
  {
    parts: [
      {
        name: "word/document.xml",
        content: @utf8.encode(
          "<w:document xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\"><w:body>" +
          body +
          "</w:body></w:document>",
        ).to_fixedarray(),
      },
      { name: "custom/opaque.bin", content: [0, 255, 42], },
    ],
  }
}

///|
test "targeted DOCX lists distinct repeated text in paragraphs and table cells" {
  let source = target_package(
    "<w:p><w:pPr/><w:r><w:rPr><w:b/></w:rPr><w:t>Acme</w:t><w:t> suffix</w:t></w:r></w:p><w:tbl><w:tblPr/><w:tr><w:tc><w:tcPr/><w:p><w:r><w:t>Acme</w:t></w:r></w:p></w:tc></w:tr></w:tbl>",
  )
  let targets = @docx.text_targets(source)
  assert_eq(targets.length(), 3)
  assert_eq(targets[0].id, "body/p:1/r:2/t:2")
  assert_eq(targets[1].id, "body/p:1/r:2/t:3")
  assert_eq(targets[2].id, "body/tbl:2/tr:2/tc:1/p:2/r:1/t:1")
  let changed = @docx.set_target_text(
    source,
    targets[2].id,
    "Acme",
    "New client",
  )
  assert_eq(@docx.text_targets(changed).map(t => t.text), [
    "Acme", " suffix", "New client",
  ])
  assert_eq(@docx.text_targets(source).map(t => t.text), [
    "Acme", " suffix", "Acme",
  ])
  assert_eq(changed.part("custom/opaque.bin"), source.part("custom/opaque.bin"))
  assert_true(changed.text("word/document.xml").contains("<w:b/>"))
}

///|
test "targeted DOCX omits unsupported wrappers and does not cross run boundaries" {
  let source = target_package(
    "<w:p><w:hyperlink><w:r><w:t>link</w:t></w:r></w:hyperlink><w:r><w:t>one</w:t></w:r><w:r><w:t>two</w:t><w:drawing><a:t>drawing</a:t></w:drawing></w:r></w:p><w:sdt><w:p><w:r><w:t>wrapped</w:t></w:r></w:p></w:sdt><w:tbl><w:tr><w:tc><w:tbl><w:tr><w:tc><w:p><w:r><w:t>nested</w:t></w:r></w:p></w:tc></w:tr></w:tbl></w:tc></w:tr></w:tbl>",
  )
  let targets = @docx.text_targets(source)
  assert_eq(targets.map(t => t.text), ["one", "two"])
  assert_true(
    try @docx.set_target_text(source, targets[0].id, "onetwo", "joined") catch {
      _ => true
    } noraise {
      _ => false
    },
  )
  assert_true(
    try
      @docx.set_target_text(
        source, "body/sdt:2/p:1/r:1/t:1", "wrapped", "changed",
      )
    catch {
      _ => true
    } noraise {
      _ => false
    },
  )
}

///|
test "targeted DOCX validates exact text including same-value requests" {
  let source = target_package("<w:p><w:r><w:t>A&#66;</w:t></w:r></w:p>")
  let id = @docx.text_targets(source)[0].id
  let same = @docx.set_target_text(source, id, "AB", "AB")
  assert_eq(same, source)
  assert_eq(same.text("word/document.xml"), source.text("word/document.xml"))
  assert_true(
    try @docx.set_target_text(source, id, "stale", "stale") catch {
      _ => true
    } noraise {
      _ => false
    },
  )
  assert_true(
    try @docx.set_target_text(source, "missing", "AB", "AB") catch {
      _ => true
    } noraise {
      _ => false
    },
  )
}

///|
test "targeted DOCX keeps empty slots stable and supports XML text and Unicode" {
  let source = target_package("<w:p><w:r><w:t/><w:t>other</w:t></w:r></w:p>")
  let targets = @docx.text_targets(source)
  let value = "  A & <B> \"雪😀\"\r\n\t "
  let changed = @docx.set_target_text(source, targets[0].id, "", value)
  assert_eq(@docx.text_targets(changed)[0].text, value)
  assert_eq(@docx.text_targets(changed)[1], targets[1])
  assert_true(
    changed.text("word/document.xml").contains("xml:space=\"preserve\""),
  )
  assert_true(changed.text("word/document.xml").contains("&#13;"))
  let erased = @docx.set_target_text(changed, targets[0].id, value, "")
  assert_eq(@docx.text_targets(erased), targets)
}

///|
test "targeted DOCX refuses fields namespace ambiguity malformed targets and invalid text" {
  for
    body in [
      "<w:p><w:r><w:fldChar w:fldCharType=\"begin\"/></w:r></w:p><w:p><w:r><w:t>cached</w:t></w:r></w:p>",
      "<w:p><w:r><w:instrText>PAGE</w:instrText></w:r></w:p>", "<w:p xmlns:w=\"urn:other\"><w:r><w:t>wrong</w:t></w:r></w:p>",
      "<w:p><w:r><w:t><w:t>nested</w:t></w:t></w:r></w:p>",
    ] {
    assert_true(
      try @docx.text_targets(target_package(body)) catch {
        _ => true
      } noraise {
        _ => false
      },
    )
  }
  let source = target_package("<w:p><w:r><w:t>valid</w:t></w:r></w:p>")
  let id = @docx.text_targets(source)[0].id
  for replacement in ["\u{0000}", "\u{0001}", "\u{FFFF}", "x".repeat(32_769)] {
    assert_true(
      try @docx.set_target_text(source, id, "valid", replacement) catch {
        _ => true
      } noraise {
        _ => false
      },
    )
  }
  assert_eq(@docx.text_targets(source)[0].text, "valid")
  assert_eq(
    @docx.text_targets(
      @docx.set_target_text(source, id, "valid", "x".repeat(32_768)),
    )[0].text.length(),
    32_768,
  )
}

///|
test "targeted DOCX preserves target-count limit and absence" {
  let row = "<w:r><w:t>x</w:t></w:r>"
  assert_eq(
    @docx.text_targets(target_package("<w:p>" + row.repeat(10_000) + "</w:p>")).length(),
    10_000,
  )
  assert_true(
    try
      @docx.text_targets(
        target_package("<w:p>" + row.repeat(10_001) + "</w:p>"),
      )
    catch {
      _ => true
    } noraise {
      _ => false
    },
  )
  assert_eq(@docx.text_targets(target_package("<w:p/>")), [])
}

///|
test "targeted DOCX splice retains lexical source around selected element" {
  let body = "<!-- <w:t>decoy</w:t> --><?kept instruction?><w:p data=\"greater > than\"><w:r><w:t><![CDATA[<w:t>literal</w:t>]]></w:t><w:t>chosen<!-- </w:t> --> text</w:t><w:t/></w:r></w:p>"
  let source = target_package(body)
  let targets = @docx.text_targets(source)
  assert_eq(targets.map(t => t.text), ["<w:t>literal</w:t>", "chosen text", ""])
  let changed = @docx.set_target_text(
    source,
    targets[1].id,
    "chosen text",
    "new",
  )
  assert_eq(
    changed.text("word/document.xml"),
    source
    .text("word/document.xml")
    .replace(
      old="<w:t>chosen<!-- </w:t> --> text</w:t>",
      new="<w:t xml:space=\"preserve\">new</w:t>",
    ),
  )
  let changed_empty = @docx.set_target_text(
    changed,
    targets[2].id,
    "",
    "filled",
  )
  assert_eq(@docx.text_targets(changed_empty).map(t => t.text), [
    "<w:t>literal</w:t>", "new", "filled",
  ])
}
