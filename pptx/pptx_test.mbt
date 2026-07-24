///|
fn minimal_png() -> FixedArray[Byte] {
  // A complete 1x1 transparent PNG: signature, IHDR, IDAT, and IEND.
  [
    0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d, 0x49,
    0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06,
    0x00, 0x00, 0x00, 0x1f, 0x15, 0xc4, 0x89, 0x00, 0x00, 0x00, 0x0d, 0x49, 0x44,
    0x41, 0x54, 0x08, 0xd7, 0x63, 0xf8, 0xcf, 0xc0, 0xf0, 0x1f, 0x00, 0x05, 0x00,
    0x01, 0xff, 0x89, 0x99, 0x3d, 0x1d, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4e,
    0x44, 0xae, 0x42, 0x60, 0x82,
  ]
}

///|
fn fixture_package() -> @opc.Package {
  {
    parts: [
      {
        name: "[Content_Types].xml",
        content: @utf8.encode(
          (
            #|<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="png" ContentType="image/png"/><Default Extension="xml" ContentType="application/xml"/></Types>
          ),
        ).to_fixedarray(),
      },
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
            #|  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide" Target="slides/slide1.xml"/>
            #|  <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide" Target="slides/slide2.xml"/>
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
        name: "ppt/slides/_rels/slide2.xml.rels",
        content: @utf8.encode(
          (
            #|<Relationships><Relationship Id="rIdImage" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="../media/image1.png"/></Relationships>
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
      { name: "ppt/media/image1.png", content: minimal_png() },
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
test "replace rejects empty find" {
  try ignore(@pptx.replace_text(fixture_package(), "", "x")) catch {
    InvalidPresentation(message~) =>
      assert_eq(message, "find text must not be empty")
    _ => fail("unexpected error")
  } noraise {
    _ => fail("expected InvalidPresentation")
  }
}

///|
test "group without grpSpPr xfrm leaves transformed child bounds unchanged" {
  let base = fixture_package()
  let slide =
    #|<p:sld xmlns:p="p" xmlns:a="a"><p:cSld><p:spTree>
    #|  <p:grpSp><p:grpSpPr/>
    #|    <p:sp><p:spPr><a:xfrm><a:off x="-11" y="22"/><a:ext cx="333" cy="444"/></a:xfrm></p:spPr></p:sp>
    #|  </p:grpSp>
    #|</p:spTree></p:cSld></p:sld>
  let parts = base.parts.map(fn(part) {
    if part.name == "ppt/slides/slide1.xml" {
      (
        { name: part.name, content: @utf8.encode(slide).to_fixedarray() } :
        @opc.Part)
    } else {
      part
    }
  })
  let presentation = @pptx.read({ parts, })
  guard presentation.slides[1].elements[0] is Shape(bounds~, ..) else {
    fail("expected shape")
  }
  assert_true(bounds == { x: -11, y: 22, width: 333, height: 444 })
}

///|
test "image validation emits one image and six warnings" {
  let base = fixture_package()
  let pictures =
    #|<p:sld xmlns:p="p" xmlns:a="a" xmlns:r="r"><p:cSld><p:spTree>
    #|<p:pic><p:blipFill><a:blip r:embed="valid"/></p:blipFill><p:spPr><a:xfrm><a:off x="1" y="2"/><a:ext cx="3" cy="4"/></a:xfrm></p:spPr></p:pic>
    #|<p:pic><p:blipFill><a:blip r:embed="spoof"/></p:blipFill></p:pic>
    #|<p:pic><p:blipFill><a:blip r:embed="external"/></p:blipFill></p:pic>
    #|<p:pic><p:blipFill><a:blip r:embed="above"/></p:blipFill></p:pic>
    #|<p:pic><p:blipFill><a:blip r:embed="missing"/></p:blipFill></p:pic>
    #|<p:pic><p:blipFill><a:blip r:embed="nonimage"/></p:blipFill></p:pic>
    #|<p:pic><p:blipFill><a:blip r:embed="badsig"/></p:blipFill></p:pic>
    #|</p:spTree></p:cSld></p:sld>
  let rels =
    #|<Relationships>
    #|<Relationship Id="valid" Type="http://purl.oclc.org/ooxml/officeDocument/relationships/image" Target="../media/image1.png"/>
    #|<Relationship Id="spoof" Type="https://attacker.invalid/image" Target="../media/image1.png"/>
    #|<Relationship Id="external" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="https://example.invalid/image.png" TargetMode="External"/>
    #|<Relationship Id="above" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="../../../evil.png"/>
    #|<Relationship Id="missing" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="../media/missing.png"/>
    #|<Relationship Id="nonimage" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="../../docProps/core.xml"/>
    #|<Relationship Id="badsig" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="../media/bad.png"/>
    #|</Relationships>
  let parts = base.parts.map(fn(part) {
    if part.name == "ppt/slides/slide1.xml" {
      (
        { name: part.name, content: @utf8.encode(pictures).to_fixedarray() } :
        @opc.Part)
    } else if part.name == "ppt/slides/_rels/slide1.xml.rels" {
      (
        { name: part.name, content: @utf8.encode(rels).to_fixedarray() } :
        @opc.Part)
    } else {
      part
    }
  })
  parts.push({
    name: "ppt/slides/_rels/slide1.xml.rels",
    content: @utf8.encode(rels).to_fixedarray(),
  })
  parts.push({
    name: "ppt/media/bad.png",
    content: @utf8.encode("not png").to_fixedarray(),
  })
  let presentation = @pptx.read({ parts, })
  assert_eq(presentation.slides[1].elements.length(), 1)
  guard presentation.slides[1].elements[0] is Image(relationship_id~, ..) else {
    fail("expected valid image")
  }
  assert_eq(relationship_id, "valid")
  assert_eq(presentation.warnings.length(), 6)
  for warning in presentation.warnings {
    assert_eq(warning.code, "pptx.invalid-image-relationship")
  }
}

///|
test "nested group composes signed rotation/flip bounds and warns on wrong image type" {
  let base = fixture_package()
  let slide =
    #|<p:sld xmlns:p="p" xmlns:a="a" xmlns:r="r"><p:cSld name="Grouped"><p:spTree>
    #|<p:grpSp><p:grpSpPr><a:xfrm><a:off x="100" y="200"/><a:ext cx="200" cy="200"/><a:chOff x="0" y="0"/><a:chExt cx="100" cy="100"/></a:xfrm></p:grpSpPr>
    #|<p:grpSp><p:grpSpPr><a:xfrm flipH="1"><a:off x="10" y="20"/><a:ext cx="100" cy="100"/><a:chOff x="0" y="0"/><a:chExt cx="100" cy="100"/></a:xfrm></p:grpSpPr>
    #|<p:sp><p:spPr><a:xfrm rot="5400000" flipV="1"><a:off x="-20" y="10"/><a:ext cx="30" cy="10"/></a:xfrm><a:prstGeom prst="rect"/></p:spPr></p:sp>
    #|<p:pic><p:blipFill><a:blip r:embed="rIdWrong"/></p:blipFill><p:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="10" cy="10"/></a:xfrm></p:spPr></p:pic>
    #|</p:grpSp></p:grpSp></p:spTree></p:cSld></p:sld>
  let rels =
    #|<Relationships><Relationship Id="rIdWrong" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink" Target="https://example.invalid" TargetMode="External"/></Relationships>
  let container = base
    .replace_text("ppt/slides/slide2.xml", slide)
    .replace_text("ppt/slides/_rels/slide2.xml.rels", rels)
  let presentation = @pptx.read(container)
  assert_eq(presentation.slides[0].elements.length(), 1)
  guard presentation.slides[0].elements[0] is Shape(bounds~, ..) else {
    fail("expected transformed shape")
  }
  assert_eq(bounds.x, 320)
  assert_eq(bounds.y, 240)
  assert_eq(bounds.width, 20)
  assert_eq(bounds.height, 60)
  assert_eq(presentation.warnings.length(), 1)
  assert_eq(presentation.warnings[0].code, "pptx.invalid-image-relationship")
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
