///|
fn scene_has_text(scene : @scene.Document, expected : String) -> Bool {
  match scene {
    TextDocument(document) =>
      document.blocks.any(block => {
        match block {
          Paragraph(runs) | Heading(_, runs) =>
            runs.any(run => run.text == expected)
          ListItem(level=_, ordered=_, runs) =>
            runs.any(run => run.text == expected)
          Table(rows) => rows.any(row => row.any(cell => cell == expected))
        }
      })
    WorkbookDocument(workbook) =>
      workbook.sheets.any(sheet => {
        sheet.cells.any(cell => {
          match cell.value {
            Text(text) => text == expected
            _ => false
          }
        })
      })
    PresentationDocument(presentation) =>
      presentation.slides.any(slide => {
        slide.elements.any(element => {
          match element {
            TextBox(runs~, ..) | Shape(text=runs, ..) =>
              runs.any(run => run.text == expected)
            Image(_) => false
          }
        })
      })
  }
}

///|
test "DocumentSession replaces text hidden by a top-level WordprocessingML wrapper" {
  let archive = @opc.open(document_session_docx_fixture())
  let customized = archive.replace_text(
    "word/document.xml", "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><w:document xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\"><w:body><w:sdt><w:sdtContent><w:p><w:r><w:t>Hidden original</w:t></w:r></w:p></w:sdtContent></w:sdt></w:body></w:document>",
  )
  let bytes = @opc.save(customized)
  let session = @moonleaf.open_session("hidden.docx", bytes)
  let original_scene = session.scene()
  assert_false(scene_has_text(original_scene, "Hidden original"))
  let changed = session.replace_text("Hidden original", "Hidden changed")
  assert_eq(changed.revision(), 1)
  assert_true(changed.is_dirty())
  assert_true(changed.scene() == original_scene)
  let copy = changed.save_as_copy()
  let copy_bytes = copy.bytes()
  let saved_archive = @opc.open(copy_bytes)
  let saved_xml = saved_archive.text("word/document.xml")
  assert_true(saved_xml.contains("Hidden changed"))
  assert_false(saved_xml.contains("Hidden original"))
  let reopened = @moonleaf.open_session("hidden.docx", copy_bytes)
  assert_true(reopened.scene() == original_scene)
  let copied_session = copy.session()
  assert_true(copied_session.scene() == reopened.scene())
  assert_eq(copied_session.filename(), reopened.filename())
  assert_true(copied_session.format() == reopened.format())
  assert_eq(copied_session.revision(), changed.revision())
  assert_eq(reopened.revision(), 0)
  assert_false(copied_session.is_dirty())
  assert_false(reopened.is_dirty())
}

///|
test "PPTX identical replacement preserves original XML bytes" {
  let archive = @opc.open(document_session_pptx_fixture())
  let source_xml = archive.text("ppt/slides/slide1.xml")
  let customized_xml = source_xml.replace(old="Hello slide", new="A&#66;")
  let customized = archive.replace_text("ppt/slides/slide1.xml", customized_xml)
  let customized_part = customized.part("ppt/slides/slide1.xml").unwrap().content
  let bytes = @opc.save(customized)
  let session = @moonleaf.open_session("deck.pptx", bytes)
  let original_scene = session.scene()
  assert_true(scene_has_text(original_scene, "AB"))

  let unchanged = session.replace_text("AB", "AB")
  assert_eq(unchanged.revision(), 0)
  assert_false(unchanged.is_dirty())
  assert_true(unchanged.scene() == original_scene)

  let copy = unchanged.save_as_copy()
  let copied = @opc.open(copy.bytes())
  assert_true(
    copied.part("ppt/slides/slide1.xml").unwrap().content == customized_part,
  )
}

///|
fn scene_cell_is_text(
  scene : @scene.Document,
  row : Int,
  column : Int,
  expected : String,
) -> Bool {
  match scene {
    WorkbookDocument(workbook) =>
      workbook.sheets.any(sheet => {
        sheet.cells.any(cell => {
          cell.row == row &&
          cell.column == column &&
          (match cell.value {
            Text(text) => text == expected
            _ => false
          })
        })
      })
    _ => false
  }
}

///|
/// Root black-box coverage for DocumentSession metadata, parity, and failures.
test "DocumentSession format filename capabilities and open parity" {
  let cases = [
    (
      "REPORT.DOCX",
      document_session_docx_fixture(),
      @moonleaf.DocumentFormat::Docx,
    ),
    ("BOOK.XLSX", document_session_xlsx_fixture(), Xlsx),
    ("DECK.PPTX", document_session_pptx_fixture(), Pptx),
  ]
  cases.each(item => {
    let session = @moonleaf.open_session(item.0, item.1)
    assert_eq(session.filename(), item.0)
    assert_true(session.format() == item.2)
    assert_true(session.scene() == @moonleaf.open(item.0, item.1))
    match item.2 {
      Docx => assert_true(scene_has_text(session.scene(), "Hello fixture"))
      Xlsx => {
        assert_true(scene_has_text(session.scene(), "Hello sheet"))
        assert_true(scene_cell_is_text(session.scene(), 1, 1, "Hello sheet"))
      }
      Pptx => assert_true(scene_has_text(session.scene(), "Hello slide"))
    }
    assert_eq(session.revision(), 0)
    assert_false(session.is_dirty())
    assert_true(session.capabilities().render_scene)
    assert_true(session.capabilities().save_as_copy)
  })
  assert_true(@moonleaf.DocumentFormat::Docx.capabilities().replace_text)
  assert_true(@moonleaf.DocumentFormat::Pptx.capabilities().replace_text)
  assert_false(@moonleaf.DocumentFormat::Xlsx.capabilities().replace_text)
  assert_true(@moonleaf.DocumentFormat::Xlsx.capabilities().set_cell_text)
  assert_false(@moonleaf.DocumentFormat::Docx.capabilities().set_cell_text)
}

///|
test "DocumentSession rejects unsupported and malformed input" {
  try @moonleaf.open_session("bad.odt", []) catch {
    UnsupportedFormat("bad.odt") => ()
    _ => fail("expected unsupported format")
  } noraise {
    _ => fail("expected unsupported format")
  }
  try @moonleaf.open_session("bad.docx", [0x00, 0xff, 0x80]) catch {
    Package(_) => ()
    _ => fail("expected malformed package")
  } noraise {
    _ => fail("expected malformed package")
  }
}

///|
test "DocumentSession rejects format-operation mismatches and empty find" {
  let xlsx = @moonleaf.open_session(
    "book.xlsx",
    document_session_xlsx_fixture(),
  )
  try xlsx.replace_text("Hello", "Goodbye") catch {
    OperationNotSupported(operation~, format~) => {
      assert_eq(operation, "replace_text")
      assert_true(format == Xlsx)
    }
    _ => fail("expected mismatch")
  } noraise {
    _ => fail("expected mismatch")
  }
  try xlsx.replace_text("same", "same") catch {
    OperationNotSupported(operation~, format~) => {
      assert_eq(operation, "replace_text")
      assert_true(format == Xlsx)
    }
    _ => fail("expected identical replacement mismatch")
  } noraise {
    _ => fail("expected identical replacement mismatch")
  }
  let docx = @moonleaf.open_session("doc.docx", document_session_docx_fixture())
  try docx.set_cell_text("Sheet1", 1, 1, "x") catch {
    OperationNotSupported(_) => ()
    _ => fail("expected mismatch")
  } noraise {
    _ => fail("expected mismatch")
  }
  try docx.replace_text("", "x") catch {
    InvalidFind(message) => assert_eq(message, "find text must not be empty")
    _ => fail("expected empty-find failure")
  } noraise {
    _ => fail("expected empty-find failure")
  }
}

///|
test "DOCX and PPTX replacement succeeds and no-op stays clean" {
  let docx = @moonleaf.open_session("doc.docx", document_session_docx_fixture())
  let docx_noop = docx.replace_text("absent", "x")
  assert_eq(docx_noop.revision(), 0)
  assert_false(docx_noop.is_dirty())
  let docx_changed = docx.replace_text("Hello fixture", "Changed")
  assert_true(scene_has_text(docx_changed.scene(), "Changed"))
  assert_eq(docx_changed.revision(), 1)
  assert_true(docx_changed.is_dirty())
  assert_eq(docx.revision(), 0)
  assert_false(docx.is_dirty())

  let pptx = @moonleaf.open_session(
    "deck.pptx",
    document_session_pptx_fixture(),
  )
  let pptx_noop = pptx.replace_text("absent", "x")
  assert_eq(pptx_noop.revision(), 0)
  assert_false(pptx_noop.is_dirty())
  let pptx_changed = pptx.replace_text("Hello slide", "Changed")
  assert_true(scene_has_text(pptx_changed.scene(), "Changed"))
  assert_eq(pptx_changed.revision(), 1)
  assert_true(pptx_changed.is_dirty())
}

///|
test "XLSX A1 edit, no-op, coordinates, formula, and merge rules" {
  let session = @moonleaf.open_session(
    "book.xlsx",
    document_session_xlsx_fixture(),
  )
  let noop = session.set_cell_text("Sheet1", 1, 1, "Hello sheet")
  assert_eq(noop.revision(), 0)
  assert_false(noop.is_dirty())
  let changed = session.set_cell_text("Sheet1", 1, 1, "Changed")
  assert_true(scene_cell_is_text(changed.scene(), 1, 1, "Changed"))
  assert_eq(changed.revision(), 1)
  assert_true(changed.is_dirty())
  try session.set_cell_text("Missing", 1, 1, "x") catch {
    SheetNotFound("Missing") => ()
    _ => fail("expected missing sheet")
  } noraise {
    _ => fail("expected missing sheet")
  }
  for coord in [(0, 1), (1, 0), (1048577, 1), (1, 16385)] {
    try session.set_cell_text("Sheet1", coord.0, coord.1, "x") catch {
      InvalidCoordinates(_) => ()
      _ => fail("expected invalid coordinates")
    } noraise {
      _ => fail("expected invalid coordinates")
    }
  }
  try session.set_cell_text("Sheet1", 1, 2, "x") catch {
    FormulaCell(_) => ()
    _ => fail("expected formula-cell failure")
  } noraise {
    _ => fail("expected formula-cell failure")
  }
  try session.set_cell_text("Sheet1", 2, 2, "x") catch {
    MergedCellNotAnchor(_) => ()
    _ => fail("expected merged non-anchor failure")
  } noraise {
    _ => fail("expected merged non-anchor failure")
  }
  let anchor = session.set_cell_text("Sheet1", 2, 1, "anchor")
  assert_true(scene_cell_is_text(anchor.scene(), 2, 1, "anchor"))
  assert_eq(anchor.revision(), 1)
}

///|
test "XLSX batch edit verifies multiple cells and rejects formula changes" {
  let session = @moonleaf.open_session(
    "book.xlsx",
    document_session_xlsx_fixture(),
  )
  let changed = session.set_cells_text("Sheet1", [
    (1, 1, "First"),
    (2, 1, "Second"),
  ])
  assert_eq(changed.revision(), 1)
  assert_true(scene_cell_is_text(changed.scene(), 1, 1, "First"))
  assert_true(scene_cell_is_text(changed.scene(), 2, 1, "Second"))
  let copy = changed.save_as_copy()
  let reopened = @moonleaf.open("edited.xlsx", copy.bytes())
  assert_true(scene_cell_is_text(reopened, 1, 1, "First"))
  assert_true(scene_cell_is_text(reopened, 2, 1, "Second"))
  try
    session.set_cells_text("Sheet1", [(1, 1, "Safe"), (1, 2, "Formula")])
  catch {
    FormulaCell(_) => ()
    _ => fail("expected formula-cell failure")
  } noraise {
    _ => fail("expected formula-cell failure")
  }
  assert_eq(session.revision(), 0)
}

///|
test "failed edits preserve original state and accessors isolate mutation" {
  let session = @moonleaf.open_session(
    "book.xlsx",
    document_session_xlsx_fixture(),
  )
  let before_scene = session.scene()
  let before_diagnostics = session.diagnostics()
  let bytes_before_failure = session.save_as_copy().bytes()
  try session.set_cell_text("Sheet1", 1, 2, "x") catch {
    _ => ()
  } noraise {
    _ => fail("expected failure")
  }
  let bytes_after_failure = session.save_as_copy().bytes()
  assert_eq(bytes_after_failure, bytes_before_failure)
  assert_eq(session.revision(), 0)
  assert_false(session.is_dirty())
  assert_true(session.scene() == before_scene)
  assert_true(session.diagnostics() == before_diagnostics)
  let returned_scene = session.scene()
  match returned_scene {
    WorkbookDocument(workbook) => workbook.sheets[0].cells.clear()
    _ => fail("expected workbook scene")
  }
  assert_true(scene_cell_is_text(session.scene(), 1, 1, "Hello sheet"))
  let diagnostics = session.diagnostics()
  diagnostics.push({ code: "injected", message: "mutated", part: None, })
  assert_true(session.diagnostics() == before_diagnostics)
}

///|
test "save_as_copy preserves exact parts and returns a clean verified copy" {
  let original = @moonleaf.open_session(
    "doc.docx",
    document_session_docx_fixture(),
  )
  let dirty = original.replace_text("Hello fixture", "Changed")
  let copy = dirty.save_as_copy()
  assert_eq(copy.session().filename(), dirty.filename())
  assert_true(copy.session().format() == dirty.format())
  assert_true(copy.session().scene() == dirty.scene())
  assert_eq(copy.session().revision(), dirty.revision())
  assert_false(copy.session().is_dirty())
  assert_true(dirty.is_dirty())
  let returned_bytes = copy.bytes()
  let original_byte0 = returned_bytes[0]
  returned_bytes[0] = original_byte0 + 1
  assert_eq(copy.bytes()[0], original_byte0)
  let package_bytes = copy.bytes()
  let reopened = @moonleaf.open_session("doc.docx", package_bytes)
  assert_true(reopened.scene() == dirty.scene())
  let archive = @opc.open(package_bytes)
  assert_true(
    archive.part("word/media/image.bin").unwrap().content == [0x00, 0xff, 0x80],
  )
  let source = @opc.open(document_session_docx_fixture())
  assert_true(
    archive.part("customXml/custom.xml").unwrap().content ==
    source.part("customXml/custom.xml").unwrap().content,
  )
  assert_true(
    archive.part("word/_rels/document.xml.rels").unwrap().content ==
    source.part("word/_rels/document.xml.rels").unwrap().content,
  )
}
