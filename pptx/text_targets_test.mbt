///|
fn target_fixture() -> @opc.Package {
  let source = fixture_package()
  let slide =
    #|<p:sld xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" show="0"><p:cSld><p:spTree>
    #|<!-- <a:t>fake</a:t> --><?keep this?>
    #|<p:sp><p:nvSpPr><p:cNvPr id="5"/></p:nvSpPr><p:txBody><a:p><a:r><a:rPr b="1"/><a:t>Acme</a:t></a:r><a:r><a:t>Acme</a:t></a:r><a:fld><a:t>field</a:t></a:fld></a:p></p:txBody></p:sp>
    #|<p:grpSp><p:sp><p:nvSpPr><p:cNvPr id="6"/></p:nvSpPr><p:txBody><a:p><a:r><a:t note="a > b"><![CDATA[Acme]]></a:t></a:r><a:r><a:t/></a:r></a:p></p:txBody></p:sp></p:grpSp>
    #|<p:graphicFrame><a:graphic><a:graphicData><a:tbl><a:tr><a:tc><a:txBody><a:p><a:r><a:t>table</a:t></a:r></a:p></a:txBody></a:tc></a:tr></a:tbl></a:graphicData></a:graphic></p:graphicFrame>
    #|</p:spTree></p:cSld></p:sld>
  source
  .replace_text("ppt/slides/slide2.xml", slide)
  .replace_text("ppt/slides/slide1.xml", slide)
}

///|
test "PPTX targets preserve presentation order repeated values groups and empty slots" {
  let source = target_fixture()
  let targets = @pptx.text_targets(source)
  assert_eq(targets.length(), 8)
  assert_eq(targets.map(t => t.text), [
    "Acme", "Acme", "Acme", "", "Acme", "Acme", "Acme", "",
  ])
  assert_eq(targets[0].slide_number, 1)
  assert_eq(targets[0].part, "ppt/slides/slide2.xml")
  assert_eq(targets[4].part, "ppt/slides/slide1.xml")
  assert_eq(targets[0].shape_id, "5")
  assert_eq(targets[2].shape_id, "6")
  assert_true(targets[0].hidden_slide)
  assert_true(targets[2].id.contains("/grpSp:"))
  assert_true(targets[0].id != targets[1].id && targets[0].id != targets[4].id)
}

///|
test "PPTX selected run changes once and keeps source lexical bytes and other parts" {
  let source = target_fixture()
  let target = @pptx.text_targets(source)[2]
  let replacement = "  Client B & <雪😀>\r\n\t "
  let result = @pptx.set_target_text(source, target.id, "Acme", replacement)
  let after = @pptx.text_targets(result)
  assert_eq(after[2].text, replacement)
  assert_eq(after[0].text, "Acme")
  assert_eq(after[1].text, "Acme")
  assert_eq(after[6].text, "Acme")
  assert_eq(@pptx.text_targets(source)[2].text, "Acme")
  for part in source.parts {
    if part.name != target.part {
      assert_eq(result.part(part.name), Some(part))
    }
  }
  let original = source.text(target.part)
  let updated = result.text(target.part)
  let before = original.split("<a:t note=").to_array()[0]
  assert_true(updated.has_prefix(before))
  assert_true(updated.contains("<!-- <a:t>fake</a:t> --><?keep this?>"))
  assert_true(updated.contains("note=\"a &gt; b\" xml:space=\"preserve\""))
}

///|
test "PPTX noops and empty targets retain identity and validate expected values" {
  let source = target_fixture()
  let targets = @pptx.text_targets(source)
  assert_eq(
    @pptx.set_target_text(source, targets[0].id, "Acme", "Acme"),
    source,
  )
  let filled = @pptx.set_target_text(source, targets[3].id, "", "new")
  assert_eq(@pptx.text_targets(filled)[3].text, "new")
  let erased = @pptx.set_target_text(filled, targets[3].id, "new", "")
  assert_eq(@pptx.text_targets(erased).map(t => t.id), targets.map(t => t.id))
  assert_true(
    try @pptx.set_target_text(source, targets[0].id, "stale", "stale") catch {
      _ => true
    } noraise {
      _ => false
    },
  )
  assert_true(
    try @pptx.set_target_text(source, "unknown", "Acme", "new") catch {
      _ => true
    } noraise {
      _ => false
    },
  )
}

///|
test "PPTX target replacement validates text boundaries" {
  let source = target_fixture()
  let id = @pptx.text_targets(source)[0].id
  for text in ["a\u0000b", "a\u0001b", "\uFFFF", "x".repeat(32769)] {
    assert_true(
      try @pptx.set_target_text(source, id, "Acme", text) catch {
        _ => true
      } noraise {
        _ => false
      },
    )
  }
  let changed = @pptx.set_target_text(source, id, "Acme", "x".repeat(32768))
  assert_eq(@pptx.text_targets(changed)[0].text.length(), 32768)
}

///|
test "PPTX targets reject unsupported namespace and malformed shape tree" {
  let source = target_fixture()
  let part = "ppt/slides/slide2.xml"
  let xml = source.text(part)
  for
    updated in [
      xml.replace_all(
        old="http://schemas.openxmlformats.org/drawingml/2006/main",
        new="urn:other",
      ),
      xml.replace_all(old="<a:r>", new="<a:r xmlns:a=\"urn:other\">"),
      xml.replace_all(old="</p:cSld>", new="<p:spTree/></p:cSld>"),
      xml.replace_all(
        old="</p:sld>",
        new="<p:cSld><p:spTree/></p:cSld></p:sld>",
      ),
      xml.replace_all(old="<a:t>Acme</a:t>", new="<a:t><a:bogus/></a:t>"),
    ] {
    assert_true(
      try @pptx.text_targets(source.replace_text(part, updated)) catch {
        _ => true
      } noraise {
        _ => false
      },
    )
  }
}

///|
test "PPTX target discovery refuses duplicate slide parts" {
  let source = target_fixture()
  let part = "ppt/_rels/presentation.xml.rels"
  let duplicated = source.replace_text(
    part,
    source
    .text(part)
    .replace_all(old="slides/slide1.xml", new="slides/slide2.xml"),
  )
  assert_true(
    try @pptx.text_targets(duplicated) catch {
      _ => true
    } noraise {
      _ => false
    },
  )
}
