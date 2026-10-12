///|
fn outline_refused(container : @opc.Package) -> Bool {
  try {
    ignore(@pptx.read_outline(container))
    false
  } catch {
    _ => true
  }
}

///|
fn outline_fixture() -> @opc.Package {
  fixture_package()
  .replace_text(
    "ppt/slides/slide2.xml",
    (
      #|<p:sld xmlns:p="p" xmlns:a="a" show="0"><p:cSld name="Review"><p:spTree>
      #|<p:sp><p:nvSpPr><p:cNvPr id="10"/><p:nvPr><p:ph type="title"/></p:nvPr></p:nvSpPr>
      #|<p:txBody><a:p><a:r><a:t>Budget &amp; 雪😀</a:t></a:r><a:br/><a:fld><a:t>2026</a:t></a:fld></a:p></p:txBody></p:sp>
      #|<p:grpSp><p:sp><p:txBody><a:p><a:r><a:t>Grouped text</a:t></a:r></a:p><a:p/></p:txBody></p:sp></p:grpSp>
      #|<p:graphicFrame><p:nvGraphicFramePr><p:cNvPr id="12"/></p:nvGraphicFramePr><a:graphic><a:graphicData><a:tbl>
      #|<a:tr><a:tc><a:txBody><a:p><a:r><a:t>Month</a:t></a:r></a:p></a:txBody></a:tc><a:tc><a:txBody><a:p><a:r><a:t>Cost</a:t></a:r></a:p></a:txBody></a:tc></a:tr>
      #|<a:tr><a:tc><a:txBody><a:p><a:r><a:t>Oct</a:t></a:r></a:p></a:txBody></a:tc><a:tc><a:txBody><a:p><a:r><a:t>42</a:t></a:r></a:p><a:p><a:r><a:t>USD</a:t></a:r></a:p></a:txBody></a:tc></a:tr>
      #|</a:tbl></a:graphicData></a:graphic></p:graphicFrame><p:pic/>
      #|</p:spTree></p:cSld></p:sld>
    ),
  )
  .replace_text(
    "ppt/slides/_rels/slide2.xml.rels",
    (
      #|<Relationships><Relationship Id="note" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/notesSlide" Target="../notesSlides/notesSlide9.xml"/></Relationships>
    ),
  )
  .replace_text(
    "ppt/notesSlides/notesSlide9.xml",
    (
      #|<p:notes xmlns:p="p" xmlns:a="a"><p:cSld><p:spTree>
      #|<p:sp><p:nvSpPr><p:cNvPr id="20"/><p:nvPr><p:ph type="body"/></p:nvPr></p:nvSpPr><p:txBody><a:p><a:r><a:t>Discuss costs.</a:t></a:r></a:p></p:txBody></p:sp>
      #|<p:sp><p:nvSpPr><p:cNvPr id="21"/><p:nvPr><p:ph type="sldNum"/></p:nvPr></p:nvSpPr><p:txBody><a:p><a:fld><a:t>99</a:t></a:fld></a:p></p:txBody></p:sp>
      #|<p:sp><p:txBody><a:p><a:r><a:t>Custom note</a:t></a:r></a:p></p:txBody></p:sp>
      #|</p:spTree></p:cSld></p:notes>
    ),
  )
}

///|
test "outline follows presentation order with titles hidden flag tables groups and notes" {
  let container = outline_fixture()
  let before = container.parts.copy()
  let outline = @pptx.read_outline(container)
  assert_eq(outline.slides.length(), 2)
  let slide = outline.slides[0]
  assert_eq(slide.number, 1)
  assert_eq(slide.part, "ppt/slides/slide2.xml")
  assert_eq(slide.name, "Review")
  assert_true(slide.hidden)
  assert_eq(slide.title, "Budget & 雪😀\n2026")
  assert_eq(slide.blocks.length(), 3)
  assert_eq(slide.blocks[0].shape_id, "10")
  assert_eq(slide.blocks[1].paragraphs, ["Grouped text", ""])
  assert_eq(slide.blocks[2].shape_id, "12")
  assert_eq(slide.blocks[2].rows, [["Month", "Cost"], ["Oct", "42\nUSD"]])
  assert_eq(slide.notes_part, Some("ppt/notesSlides/notesSlide9.xml"))
  assert_eq(slide.notes.length(), 2)
  assert_eq(slide.notes[0].paragraphs, ["Discuss costs."])
  assert_eq(slide.notes[1].paragraphs, ["Custom note"])
  assert_eq(outline.slides[1].part, "ppt/slides/slide1.xml")
  assert_eq(outline.slides[1].notes_part, None)
  assert_false(outline.slides[1].hidden)
  assert_true(outline.warnings.any(w => w.contains("picture omitted")))
  assert_eq(container.parts, before)
}

///|
test "outline strict notes relationship type works and missing linked notes fails" {
  let container = outline_fixture()
  let rels = container.text("ppt/slides/_rels/slide2.xml.rels")
  let strict = container.replace_text(
    "ppt/slides/_rels/slide2.xml.rels",
    rels.replace_all(
      old="http://schemas.openxmlformats.org/officeDocument/2006/relationships/notesSlide",
      new="http://purl.oclc.org/ooxml/officeDocument/relationships/notesSlide",
    ),
  )
  assert_eq(@pptx.read_outline(strict).slides[0].notes.length(), 2)
  let missing = container.replace_text(
    "ppt/slides/_rels/slide2.xml.rels",
    rels.replace_all(old="notesSlide9.xml", new="missing.xml"),
  )
  assert_true(outline_refused(missing))
}

///|
test "outline refuses external ambiguous traversal malformed and wrong-root notes" {
  let container = outline_fixture()
  let path = "ppt/slides/_rels/slide2.xml.rels"
  let rels = container.text(path)
  for
    source in [
      rels.replace_all(old="Target=", new="TargetMode=\"External\" Target="),
      rels.replace_all(
        old="</Relationships>",
        new="<Relationship Id=\"note2\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/notesSlide\" Target=\"../notesSlides/notesSlide9.xml\"/></Relationships>",
      ),
      rels.replace_all(
        old="../notesSlides/notesSlide9.xml",
        new="../../../outside.xml",
      ),
      "<Relationships>",
    ] {
    assert_true(outline_refused(container.replace_text(path, source)))
  }
  for source in ["<p:notes>", "<p:sld/>", "<p:notes><p:cSld/></p:notes>"] {
    assert_true(
      outline_refused(
        container.replace_text("ppt/notesSlides/notesSlide9.xml", source),
      ),
    )
  }
}

///|
test "outline emits merge and unsupported chart warnings without false content" {
  let container = outline_fixture()
  let xml = container.text("ppt/slides/slide2.xml")
  let modified = container.replace_text(
    "ppt/slides/slide2.xml",
    xml
    .replace_all(old="<a:tc>", new="<a:tc gridSpan=\"2\">")
    .replace_all(
      old="<p:pic/>",
      new="<p:graphicFrame><a:graphic><a:graphicData><c:chart/></a:graphicData></a:graphic></p:graphicFrame>",
    ),
  )
  let outline = @pptx.read_outline(modified)
  assert_true(outline.warnings.any(w => w.contains("merged table")))
  assert_true(outline.warnings.any(w => w.contains("non-table graphic frame")))
  assert_eq(outline.slides[0].blocks.length(), 3)
}

///|
test "outline permits 200 slides and refuses 201" {
  let container = outline_fixture()
  for count in [200, 201] {
    let ids = Array::make(count, "<p:sldId r:id=\"rId1\"/>").join("")
    let modified = container.replace_text(
      "ppt/presentation.xml",
      "<p:presentation><p:sldIdLst>" + ids + "</p:sldIdLst></p:presentation>",
    )
    if count == 200 {
      assert_eq(@pptx.read_outline(modified).slides.length(), 200)
    } else {
      assert_true(outline_refused(modified))
    }
  }
}

///|
test "outline permits 256 table columns and refuses 257" {
  for count in [256, 257] {
    let cells = Array::make(count, "<a:tc/>").join("")
    let container = fixture_package().replace_text(
      "ppt/slides/slide2.xml",
      "<p:sld><p:cSld><p:spTree><p:graphicFrame><a:graphic><a:graphicData><a:tbl><a:tr>" +
      cells +
      "</a:tr></a:tbl></a:graphicData></a:graphic></p:graphicFrame></p:spTree></p:cSld></p:sld>",
    )
    if count == 256 {
      assert_eq(
        @pptx.read_outline(container).slides[0].blocks[0].rows[0].length(),
        256,
      )
    } else {
      assert_true(outline_refused(container))
    }
  }
}

///|
test "outline markdown escapes document markup and keeps table and notes provenance" {
  let container = outline_fixture()
  let xml = container.text("ppt/slides/slide2.xml")
  let outline = @pptx.read_outline(
    container.replace_text(
      "ppt/slides/slide2.xml",
      xml.replace_all(old="Month", new="&lt;script&gt;[x](url)|*`"),
    ),
  )
  let markdown = outline.to_markdown()
  assert_true(markdown.contains("## Slide 1 (hidden)"))
  assert_true(markdown.contains("ppt/notesSlides/notesSlide9.xml"))
  assert_true(markdown.contains("&lt;script&gt;\\[x\\](url)\\|\\*\\`"))
  assert_false(markdown.contains("<script>"))
  assert_true(markdown.contains("| Oct | 42<br>USD |"))
  assert_true(markdown.contains("Discuss costs."))
  assert_false(markdown.contains("99"))
}

///|
test "outline table row ceiling includes empty cells" {
  for count in [1000, 1001] {
    let rows = Array::make(count, "<a:tr><a:tc/></a:tr>").join("")
    let container = fixture_package().replace_text(
      "ppt/slides/slide2.xml",
      "<p:sld><p:cSld><p:spTree><p:graphicFrame><a:graphic><a:graphicData><a:tbl>" +
      rows +
      "</a:tbl></a:graphicData></a:graphic></p:graphicFrame></p:spTree></p:cSld></p:sld>",
    )
    if count == 1000 {
      assert_eq(
        @pptx.read_outline(container).slides[0].blocks[0].rows.length(),
        1000,
      )
    } else {
      assert_true(outline_refused(container))
    }
  }
}

///|
test "outline cumulative text ceiling includes slide names" {
  for count in [1_999_994, 1_999_995] {
    let text = Array::make(count, "x").join("")
    let container = fixture_package()
      .replace_text(
        "ppt/presentation.xml", "<p:presentation><p:sldIdLst><p:sldId r:id=\"rId1\"/></p:sldIdLst></p:presentation>",
      )
      .replace_text(
        "ppt/slides/slide1.xml",
        "<p:sld><p:cSld><p:spTree><p:sp><p:txBody><a:p><a:r><a:t>" +
        text +
        "</a:t></a:r></a:p></p:txBody></p:sp></p:spTree></p:cSld></p:sld>",
      )
    if count == 1_999_994 {
      assert_eq(
        @pptx.read_outline(container).slides[0].blocks[0].paragraphs[0].length(),
        count,
      )
    } else {
      assert_true(outline_refused(container))
    }
  }
}

///|
test "outline counts metadata items toward the shape ceiling" {
  for count in [100_000, 100_001] {
    let items = Array::make(count, "<p:nvGrpSpPr/>").join("")
    let container = fixture_package()
      .replace_text(
        "ppt/presentation.xml", "<p:presentation><p:sldIdLst><p:sldId r:id=\"rId1\"/></p:sldIdLst></p:presentation>",
      )
      .replace_text(
        "ppt/slides/slide1.xml",
        "<p:sld><p:cSld><p:spTree>" + items + "</p:spTree></p:cSld></p:sld>",
      )
    if count == 100_000 {
      assert_eq(@pptx.read_outline(container).slides[0].blocks.length(), 0)
    } else {
      assert_true(outline_refused(container))
    }
  }
}
