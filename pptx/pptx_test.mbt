///|
fn fixture_package() -> @opc.Package {
  {
    parts: [
      {
        name: "ppt/presentation.xml",
        content: @utf8.encode(
          (
            #|<p:presentation xmlns:p="p" xmlns:r="r">
            #|  <p:sldIdLst>
            #|    <p:sldId id="256" r:id="rId2"/>
            #|    <p:sldId id="257" r:id="rId1"/>
            #|  </p:sldIdLst>
            #|  <p:sldSz cx="12192000" cy="6858000"/>
            #|</p:presentation>
          ),
        ).to_fixedarray(),
      },
      {
        name: "ppt/_rels/presentation.xml.rels",
        content: @utf8.encode(
          (
            #|<Relationships>
            #|  <Relationship Id="rId1" Type="slide" Target="slides/slide1.xml"/>
            #|  <Relationship Id="rId2" Type="slide" Target="slides/slide2.xml"/>
            #|</Relationships>
          ),
        ).to_fixedarray(),
      },
      {
        name: "ppt/slides/slide2.xml",
        content: @utf8.encode(
          (
            #|<p:sld xmlns:p="p" xmlns:a="a" xmlns:r="r">
            #|  <p:cSld name="Overview"><p:spTree>
            #|    <p:sp>
            #|      <p:nvSpPr><p:cNvSpPr txBox="1"/></p:nvSpPr>
            #|      <p:spPr><a:xfrm><a:off x="10" y="20"/><a:ext cx="300" cy="400"/></a:xfrm></p:spPr>
            #|      <p:txBody><a:p><a:r><a:rPr b="1" sz="1800"><a:solidFill><a:srgbClr val="FF0000"/></a:solidFill></a:rPr><a:t>Hello &amp; Moon</a:t></a:r></a:p></p:txBody>
            #|    </p:sp>
            #|    <p:pic>
            #|      <p:blipFill><a:blip r:embed="rIdImage"/></p:blipFill>
            #|      <p:spPr><a:xfrm><a:off x="500" y="600"/><a:ext cx="700" cy="800"/></a:xfrm></p:spPr>
            #|    </p:pic>
            #|  </p:spTree></p:cSld>
            #|</p:sld>
          ),
        ).to_fixedarray(),
      },
      {
        name: "ppt/slides/slide1.xml",
        content: @utf8.encode(
          (
            #|<p:sld xmlns:p="p" xmlns:a="a"><p:cSld><p:spTree>
            #|  <p:sp>
            #|    <p:spPr><a:xfrm><a:off x="1" y="2"/><a:ext cx="3" cy="4"/></a:xfrm><a:prstGeom prst="roundRect"/></p:spPr>
            #|    <p:txBody><a:p><a:r><a:t>Second</a:t></a:r></a:p></p:txBody>
            #|  </p:sp>
            #|</p:spTree></p:cSld></p:sld>
          ),
        ).to_fixedarray(),
      },
      {
        name: "docProps/core.xml",
        content: @utf8.encode("<core>unchanged</core>").to_fixedarray(),
      },
    ],
  }
}

///|
test "read presentation order, size, text, shapes and images" {
  let presentation = @pptx.read(fixture_package())
  assert_eq(presentation.slides.length(), 2)
  let first = presentation.slides[0]
  assert_eq(first.name, "Overview")
  assert_eq(first.width, 12192000)
  assert_eq(first.height, 6858000)
  assert_eq(first.elements.length(), 2)
  guard first.elements[0] is TextBox(bounds~, runs~) else {
    fail("expected text box")
  }
  assert_true(bounds == { x: 10, y: 20, width: 300, height: 400 })
  assert_eq(runs.length(), 1)
  assert_eq(runs[0].text, "Hello & Moon")
  assert_true(runs[0].style.bold)
  assert_true(runs[0].style.font_size_half_points == Some(36))
  assert_true(runs[0].style.color == Some("FF0000"))
  guard first.elements[1] is Image(bounds=image_bounds, relationship_id~) else {
    fail("expected image")
  }
  assert_true(image_bounds == { x: 500, y: 600, width: 700, height: 800 })
  assert_eq(relationship_id, "rIdImage")
  guard presentation.slides[1].elements[0]
    is Shape(kind~, bounds=shape_bounds, text~) else {
    fail("expected preset shape")
  }
  assert_eq(kind, "roundRect")
  assert_true(shape_bounds == { x: 1, y: 2, width: 3, height: 4 })
  assert_eq(text[0].text, "Second")
}

///|
test "replace exact slide text while preserving unrelated parts" {
  let container = fixture_package()
  let original_properties = container.text("docProps/core.xml")
  let updated = @pptx.replace_text(container, "Hello & Moon", "New <Title>")
  assert_eq(updated.text("docProps/core.xml"), original_properties)
  let slide = updated.text("ppt/slides/slide2.xml")
  assert_true(slide.contains("<a:t>New &lt;Title&gt;</a:t>"))
  assert_true(slide.contains("<a:off x=\"10\" y=\"20\"/>"))
  assert_eq(
    updated.text("ppt/slides/slide1.xml"),
    container.text("ppt/slides/slide1.xml"),
  )
}

///|
test "read reports a PPTX-specific error for a missing slide relationship" {
  let container : @opc.Package = {
    parts: [
      {
        name: "ppt/presentation.xml",
        content: @utf8.encode(
          (
            #|<p:presentation xmlns:p="p" xmlns:r="r">
            #|  <p:sldIdLst><p:sldId id="256" r:id="rIdMissing"/></p:sldIdLst>
            #|  <p:sldSz cx="100" cy="100"/>
            #|</p:presentation>
          ),
        ).to_fixedarray(),
      },
      {
        name: "ppt/_rels/presentation.xml.rels",
        content: @utf8.encode("<Relationships/>").to_fixedarray(),
      },
    ],
  }
  try @pptx.read(container) catch {
    MissingSlide(relationship_id="rIdMissing") => ()
    error => fail("unexpected error: \{to_repr(error)}")
  } noraise {
    _ => fail("expected missing slide relationship error")
  }
}
