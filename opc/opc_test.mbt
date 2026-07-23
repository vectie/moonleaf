///|
test "open, edit, and save an OPC package without dropping unknown parts" {
  let bytes = @fzip.zip_sync([
    (
      "[Content_Types].xml",
      @fzip.str_to_u8("<Types xmlns=\"urn:content-types\"/>"),
    ),
    ("custom/data.bin", [b'\x01', b'\x02']),
    ("word/document.xml", @fzip.str_to_u8("<document>before</document>")),
  ])
  let archive = @opc.open(bytes)
  assert_eq(archive.text("word/document.xml"), "<document>before</document>")
  let edited = archive.replace_text(
    "word/document.xml", "<document>after</document>",
  )
  let reopened = @opc.open(@opc.save(edited))
  assert_eq(reopened.text("word/document.xml"), "<document>after</document>")
  assert_eq(reopened.part("custom/data.bin").unwrap().content.length(), 2)
}

///|
test "resolve relationship targets relative to their source part" {
  assert_eq(
    @opc.relationships_part_name("word/document.xml"),
    "word/_rels/document.xml.rels",
  )
  assert_eq(
    @opc.resolve_target("ppt/presentation.xml", "slides/slide1.xml"),
    "ppt/slides/slide1.xml",
  )
  assert_eq(
    @opc.resolve_target("xl/worksheets/sheet1.xml", "../sharedStrings.xml"),
    "xl/sharedStrings.xml",
  )
}

///|
test "relationship target keeps valid leading-parent normalization" {
  assert_eq(
    @opc.resolve_target("word/document.xml", "../media/image.png"),
    "media/image.png",
  )
}

///|
test "relationship target cannot traverse above package root" {
  try @opc.resolve_target("word/document.xml", "../../secret.xml") catch {
    InvalidPackage(message) =>
      assert_eq(
        message, "relationship target traverses above package root: ../../secret.xml",
      )
    _ => fail("unexpected package error")
  } noraise {
    _ => fail("expected above-root target to raise")
  }
}

///|
test "duplicate relationship Id is rejected" {
  let bytes = @fzip.zip_sync([
    (
      "[Content_Types].xml",
      @fzip.str_to_u8("<Types xmlns=\"urn:content-types\"/>"),
    ),
    (
      "_rels/.rels",
      @fzip.str_to_u8(
        (
          #|<Relationships>
          #|  <Relationship Id="rId1" Type="type-a" Target="a.xml"/>
          #|  <Relationship Id="rId1" Type="type-b" Target="b.xml"/>
          #|</Relationships>
        ),
      ),
    ),
  ])
  let archive = @opc.open(bytes)
  try archive.relationships("") catch {
    InvalidPackage(message) =>
      assert_eq(message, "duplicate relationship Id: rId1")
    _ => fail("unexpected package error")
  } noraise {
    _ => fail("expected duplicate relationship Id to raise")
  }
}
