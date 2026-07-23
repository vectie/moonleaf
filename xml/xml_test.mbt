///|
test "parse namespaces, attributes, entities, comments, and cdata" {
  let root = @xml.parse(
    "<?xml version=\"1.0\"?><w:root answer=\"42\"><!--x--><w:p>A &amp; B</w:p><![CDATA[<raw>]]></w:root>",
  )
  assert_eq(root.local_name(), "root")
  assert_true(root.attribute("answer") is Some("42"))
  assert_eq(root.children_named("p")[0].text_content(), "A & B")
  assert_eq(root.text_content(), "A & B<raw>")
}

///|
test "serialize escapes content" {
  let element : @xml.Element = {
    name: "x",
    attributes: [{ name: "a", value: "\"&" }],
    children: [@xml.Node::Text("<ok>")],
  }
  assert_eq(@xml.serialize(element), "<x a=\"&quot;&amp;\">&lt;ok&gt;</x>")
}

///|
test "reject mismatched closing element" {
  try @xml.parse("<a></b>") catch {
    @xml.XmlError::InvalidXml(offset=_, message~) =>
      assert_eq(message, "mismatched closing element b")
  } noraise {
    _ => fail("expected invalid XML")
  }
}
