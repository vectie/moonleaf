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
    attributes: [{ name: "a", value: "\"&", }],
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

///|
test "prefixed parse serialize retains namespace declarations" {
  let source = "<w:root xmlns:w=\"urn:word\"><w:p>ok</w:p></w:root>"
  assert_eq(@xml.serialize(@xml.parse(source)), source)
}

///|
fn expect_limit(
  source : String,
  options : @xml.ParseOptions,
) -> Unit raise Failure {
  try @xml.parse_with_options(source, options) catch {
    @xml.XmlError::InvalidXml(offset=_, message=_) => ()
  } noraise {
    _ => fail("expected resource-limit rejection")
  }
}

///|
test "parse resource limits" {
  let defaults = @xml.ParseOptions::safe_defaults()
  expect_limit("<root/>", { ..defaults, max_input_utf16: 6, })
  expect_limit("<a><b/></a>", { ..defaults, max_depth: 1, })
  expect_limit("<a><b/></a>", { ..defaults, max_nodes: 1, })
  expect_limit("<a x=\"1\"/>", { ..defaults, max_attributes_per_element: 0, })
  expect_limit("<a>xy</a>", { ..defaults, max_total_decoded_text: 1, })
}

///|
test "reject DTD and undeclared entities" {
  try @xml.parse("<!DOCTYPE a><a/>") catch {
    @xml.XmlError::InvalidXml(offset=_, message=_) => ()
  } noraise {
    _ => fail("expected DTD rejection")
  }
  try @xml.parse("<a>&declared;</a>") catch {
    @xml.XmlError::InvalidXml(offset=_, message=_) => ()
  } noraise {
    _ => fail("expected entity rejection")
  }
}

///|
test "accept processing instructions around root" {
  assert_eq(@xml.parse("<?foo?><root/>").name, "root")
  assert_eq(@xml.parse("<root/><?foo?>").name, "root")
  assert_eq(@xml.parse("\u{FEFF}<?xml version=\"1.0\"?><root/>").name, "root")
}

///|
fn expect_invalid_entity(source : String) -> Unit raise Failure {
  try @xml.parse(source) catch {
    @xml.XmlError::InvalidXml(offset=_, message=_) => ()
  } noraise {
    _ => fail("expected invalid numeric entity")
  }
}

///|
test "reject numeric entity overflow and XML-invalid scalars" {
  expect_invalid_entity("<a>&#1114112;</a>")
  expect_invalid_entity("<a>&#999999999999999999999999999999999999;</a>")
  expect_invalid_entity("<a>&#x110000;</a>")
  expect_invalid_entity("<a>&#xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;</a>")
  expect_invalid_entity("<a>&#xD800;</a>")
  expect_invalid_entity("<a>&#0;</a>")
  expect_invalid_entity("<a>&#1;</a>")
}
