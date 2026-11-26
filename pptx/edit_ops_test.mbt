///|
test "pptx apply_edit_ops clones templates, populates text, sets notes, reorders, and deletes" {
  let bytes = @pptx.create({
    "title": "Template Deck",
    "slides": [
      { "title": "Cover Title", "bullets": ["Subtitle here"] },
      {
        "title": "Content Slide",
        "bullets": ["Point A", "Point B"],
        "notes": "Old note",
      },
    ],
  })
  let pkg = @opc.open(bytes)
  let summary = @pptx.template_summary(pkg)
  assert_true(summary is { "slide_count": Number(2.0, ..), .. })

  let (updated, report) = @pptx.apply_edit_ops(pkg, {
    "ops": [
      { "op": "clone_slide", "template_slide": 1, "insert_at": 2 },
      {
        "op": "replace_shape_text",
        "slide": 2,
        "shape_index": 0,
        "paragraphs": ["Cloned Section"],
      },
      {
        "op": "replace_shape_text",
        "slide": 2,
        "shape_index": 1,
        "paragraphs": ["First bullet", "Second bullet"],
      },
      { "op": "set_notes", "slide": 2, "text": "Speaker script for slide 3" },
      { "op": "reorder_slides", "order": [0, 2, 1] },
      { "op": "delete_slide", "slide": 2 },
    ],
  })
  assert_true(report is { "applied": Number(6.0, ..), .. })
  let outline = @pptx.read_outline(updated)
  assert_eq(outline.slides.length(), 2)
  assert_eq(outline.slides[1].blocks[0].paragraphs, ["Cloned Section"])
  assert_eq(outline.slides[1].notes[0].paragraphs, [
    "Speaker script for slide 3",
  ])
}
