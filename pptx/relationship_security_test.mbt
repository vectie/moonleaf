///|
fn package_with_slide_relationship(
  type_ : String,
  target : String,
  external : Bool,
) -> @opc.Package {
  let target_mode = if external { " TargetMode=\"External\"" } else { "" }
  {
    parts: [
      {
        name: "ppt/presentation.xml",
        content: @utf8.encode(
          (
            #|<p:presentation xmlns:p="p" xmlns:r="r"><p:sldIdLst><p:sldId id="256" r:id="rIdBad"/></p:sldIdLst><p:sldSz cx="1" cy="1"/></p:presentation>
          ),
        ).to_fixedarray(),
      },
      {
        name: "ppt/slides/slide1.xml",
        content: @utf8.encode(
          (
            #|<p:sld xmlns:p="p"><p:cSld><p:spTree/></p:cSld></p:sld>
          ),
        ).to_fixedarray(),
      },
      {
        name: "ppt/_rels/presentation.xml.rels",
        content: @utf8.encode(
          "<Relationships><Relationship Id=\"rIdBad\" Type=\"\{type_}\" Target=\"\{target}\"\{target_mode}/></Relationships>",
        ).to_fixedarray(),
      },
    ],
  }
}

///|
fn assert_invalid_relationship(
  container : @opc.Package,
  target : String,
) -> Unit raise {
  try @pptx.read(container) catch {
    InvalidPresentation(message~) => {
      assert_true(message.contains("rIdBad"))
      assert_true(message.contains(target))
    }
    _ => fail("expected InvalidPresentation")
  } noraise {
    _ => fail("expected invalid presentation")
  }
}

///|
test "accept strict slide relationship" {
  let presentation = @pptx.read(
    package_with_slide_relationship(
      "http://purl.oclc.org/ooxml/officeDocument/relationships/slide", "slides/slide1.xml",
      false,
    ),
  )
  assert_eq(presentation.slides.length(), 1)
}

///|
test "reject above-root slide target with relationship context" {
  assert_invalid_relationship(
    package_with_slide_relationship(
      "http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide",
      "../../evil.xml", false,
    ),
    "../../evil.xml",
  )
}

///|
test "reject external slide relationship" {
  assert_invalid_relationship(
    package_with_slide_relationship(
      "http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide",
      "https://example.invalid/slide.xml", true,
    ),
    "https://example.invalid/slide.xml",
  )
}

///|
test "reject suffix-spoof slide relationship" {
  assert_invalid_relationship(
    package_with_slide_relationship(
      "https://attacker.invalid/slide", "slides/slide1.xml", false,
    ),
    "slides/slide1.xml",
  )
}

///|
test "reject wrong-type relationship used as slide" {
  assert_invalid_relationship(
    package_with_slide_relationship(
      "http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink",
      "slides/slide1.xml", false,
    ),
    "slides/slide1.xml",
  )
}
