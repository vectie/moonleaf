///|
fn record_spec() -> @jsontable.XmlRecordSpec raise {
  @jsontable.parse_xml_spec(
    (
      #|{"record_path":["catalog","item"],"fields":[
      #|{"name":"sku","path":[],"attribute":"sku"},
      #|{"name":"name","path":["name"]},
      #|{"name":"price","path":["price"]},
      #|{"name":"tags","path":["tag"],"repeated":"join","separator":" | "}]}
    ),
  )
}

///|
test "XML records preserve identifiers missing empty entities Unicode and reopen exports" {
  let source =
    #|<?xml version="1.0" encoding="UTF-8"?>
    #|<catalog><item sku="001"><name>東京 &amp; 茶 &#x1f375;</name><price>12.50</price><tag>a</tag><tag><![CDATA[b < c]]></tag></item>
    #|<item sku="002"><name/><price></price></item><item sku="003"/></catalog>
  let table = @jsontable.parse_xml_records(source, record_spec())
  assert_eq(table.columns, ["sku", "name", "price", "tags"])
  assert_eq(table.rows, [
    [Text("001"), Text("東京 & 茶 🍵"), Text("12.50"), Text("a | b < c")],
    [Text("002"), Text(""), Text(""), Empty],
    [Text("003"), Empty, Empty, Empty],
  ])
  let json = @json.parse(table.export_json())
  guard json is Array(rows) else { fail("Expected JSON array") }
  assert_true(rows[1] is { "name": String(""), "tags": Null, .. })
  assert_true(rows[2] is { "sku": String("003"), "name": Null, .. })
  assert_eq(@jsontable.parse(table.export_json(omit_empty=true)), table)
  assert_eq(
    @csv.parse(table.export_csv()).rows,
    [table.columns] + table.text_rows(),
  )
  let workbook = @xlsx.read(@opc.open(table.export_xlsx()))
  assert_true(workbook.sheets[0].cells.any(cell => cell.value == Text("001")))
  assert_true(
    workbook.sheets[0].cells.any(cell => cell.value == Text("東京 & 茶 🍵")),
  )
  assert_true(
    workbook.sheets[0].cells.any(cell => {
      cell.row == 3 && cell.column == 2 && cell.value == Text("")
    }),
  )
  assert_true(
    !workbook.sheets[0].cells.any(cell => {
      cell.row == 4 && cell.column == 2 && cell.value != Empty
    }),
  )
}

///|
test "XML record namespace matching follows URI scope and unqualified attributes" {
  let spec = @jsontable.parse_xml_spec(
    (
      #|{"record_path":["{urn:c}catalog","{urn:c}item"],"fields":[
      #|{"name":"id","path":[],"attribute":"id"},
      #|{"name":"supplier","path":[],"attribute":"{urn:s}id"},
      #|{"name":"name","path":["{urn:c}name"]},
      #|{"name":"plain","path":["name"]},
      #|{"name":"language","path":[],"attribute":"{http://www.w3.org/XML/1998/namespace}lang"}]}
    ),
  )
  let table = @jsontable.parse_xml_records(
    (
      #|<catalog xmlns="urn:c" xmlns:s="urn:s"><item id="001" s:id="S1" xml:lang="ja"><name>one</name><name xmlns="">plain</name></item>
      #|<x:item xmlns:x="urn:c" xmlns:s="urn:other" id="002" s:id="wrong"><x:name>two</x:name></x:item>
      #|<item xmlns="urn:other" id="not-a-record"/></catalog>
    ),
    spec,
  )
  assert_eq(table.rows, [
    [Text("001"), Text("S1"), Text("one"), Text("plain"), Text("ja")],
    [Text("002"), Empty, Text("two"), Empty, Empty],
  ])
}

///|
test "XML record nested field paths attribute absence and explicit repeated join" {
  let spec = @jsontable.parse_xml_spec(
    (
      #|{"record_path":["r","row"],"fields":[
      #|{"name":"nested","path":["address","city"]},
      #|{"name":"value","path":["tag"],"attribute":"code","repeated":"join","separator":";"}]}
    ),
  )
  let table = @jsontable.parse_xml_records(
    "<r><row><address><city>Zürich</city></address><tag code=''/><tag/><tag code='03'/></row><row><tag/></row></r>",
    spec,
  )
  assert_eq(table.rows, [[Text("Zürich"), Text(";;03")], [Empty, Empty]])
  let strict = @jsontable.parse_xml_spec(
    "{\"record_path\":[\"r\",\"row\"],\"fields\":[{\"name\":\"x\",\"path\":[\"x\"]}]}",
  )
  assert_true(
    try
      @jsontable.parse_xml_records("<r><row><x>a</x><x>b</x></row></r>", strict)
    catch {
      value => value is RepeatedXmlField(row=1, column="x")
    } noraise {
      _ => false
    },
  )
  assert_true(
    try
      @jsontable.parse_xml_records("<r><row><x>a<b>b</b></x></row></r>", strict)
    catch {
      value => value is NonLeafXmlField(row=1, column="x")
    } noraise {
      _ => false
    },
  )
}

///|
test "XML record intake feeds existing lookup and grouped summaries" {
  let catalog = @jsontable.parse_xml_records(
    "<catalog><item sku='001'><name>Tea</name><price>12.50</price></item><item sku='003'><name>Glass</name><price>5.25</price></item></catalog>",
    record_spec(),
  )
  let orders_spec = @jsontable.parse_xml_spec(
    (
      #|{"record_path":["orders","order"],"fields":[{"name":"sku","path":[],"attribute":"sku"},{"name":"quantity","path":["quantity"]}]}
    ),
  )
  let orders = @jsontable.parse_xml_records(
    "<orders><order sku='001'><quantity>4</quantity></order><order sku='003'><quantity>2</quantity></order><order sku='001'><quantity>1</quantity></order><order sku='009'><quantity>3</quantity></order></orders>",
    orders_spec,
  )
  let enriched = orders.lookup(
    catalog,
    source_key="sku",
    lookup_key="sku",
    columns=["name", "price"],
    prefix="catalog.",
  )
  assert_eq(enriched.lookup_rows, [Some(1), Some(2), Some(1), None])
  assert_eq(enriched.table.text_rows()[0], ["001", "4", "Tea", "12.50"])
  let summary = enriched.table.summarize(group_by=["sku"], measures=[
    { name: "units", operation: Sum("quantity"), },
  ])
  assert_eq(summary.text_rows(), [["001", "5"], ["003", "2"], ["009", "3"]])
}

///|
test "XML records normalize literal XML whitespace without trimming data or references" {
  let spec = @jsontable.parse_xml_spec(
    "{\"record_path\":[\"r\"],\"fields\":[{\"name\":\"a\",\"path\":[],\"attribute\":\"a\"},{\"name\":\"text\",\"path\":[]}]}",
  )
  let table = @jsontable.parse_xml_records(
    "\u{FEFF}<?xml version='1.0' standalone='yes'?><r a=' a\t\r\nb&#x9;&#13; '> x\r\ny\r z </r>",
    spec,
  )
  assert_eq(table.text_rows(), [[" a  b\t\r ", " x\ny\n z "]])
}

///|
test "XML records reject malformed XML entities DTD external resources and tolerant parser gaps" {
  let spec = record_spec()
  for
    source in [
      "<catalog><item></catalog>", "<catalog/><catalog/>", "<catalog><item sku='1' sku='2'/></catalog>",
      "<catalog><item sku='1'sku2='2'/></catalog>", "<catalog>&unknown;</catalog>",
      "<catalog>&#0;</catalog>", "<catalog>bad\u{0001}</catalog>", "<catalog>bad]]></catalog>",
      "<catalog><!-- bad--comment --></catalog>", "<catalog><!-- end---></catalog>",
      "<!DOCTYPE catalog SYSTEM 'file:///etc/passwd'><catalog/>", "<!DOCTYPE catalog [<!ENTITY x SYSTEM 'https://example.invalid/data'>]><catalog>&x;</catalog>",
      "<catalog><![ENTITY x 'abc']></catalog>", "<?xml-stylesheet href='https://example.invalid/x'?><catalog/>",
      "<?xml version='1.1'?><catalog/>", "<?xml version='1.0' encoding='ISO-8859-1'?><catalog/>",
      "<catalog><?xml version='1.0'?></catalog>", "<catalog><1item/></catalog>",
    ] {
    assert_true(
      try @jsontable.parse_xml_records(source, spec) catch {
        _ => true
      } noraise {
        _ => false
      },
    )
  }
}

///|
test "XML records reject unbound reserved and duplicate expanded namespaces" {
  let spec = record_spec()
  for
    source in [
      "<catalog><x:item/></catalog>", "<catalog><item x:sku='001'/></catalog>", "<catalog xmlns:xml='urn:wrong'/>",
      "<catalog xmlns:x='http://www.w3.org/XML/1998/namespace'/>", "<catalog xmlns='http://www.w3.org/2000/xmlns/'/>",
      "<catalog xmlns:xmlns='urn:no'/>", "<catalog xmlns:x=''/>", "<catalog xmlns='urn:a b'/>",
      "<catalog xmlns:a='urn:x' xmlns:b='urn:x'><item a:id='1' b:id='2'/></catalog>",
      "<catalog><item xmlns:a='urn:x' a:1id='1'/></catalog>",
    ] {
    assert_true(
      try @jsontable.parse_xml_records(source, spec) catch {
        value => value is InvalidRecordXml(_)
      } noraise {
        _ => false
      },
    )
  }
}

///|
test "XML record empty selection retains columns and root mismatch is explicit" {
  let spec = record_spec()
  let table = @jsontable.parse_xml_records(
    "<catalog><!-- no items --></catalog>", spec,
  )
  assert_eq(table.columns, ["sku", "name", "price", "tags"])
  assert_eq(table.rows, [])
  assert_eq(table.export_json(), "[]")
  assert_true(
    try @jsontable.parse_xml_records("<other/>", spec) catch {
      value => value is InvalidRecordXml(_)
    } noraise {
      _ => false
    },
  )
  let unicode = @jsontable.parse_xml_spec(
    "{\"record_path\":[\"目录\",\"𐐀\"],\"fields\":[{\"name\":\"text\",\"path\":[]}]}",
  )
  assert_eq(
    @jsontable.parse_xml_records("<目录><𐐀>café</𐐀></目录>", unicode).text_rows(),
    [["café"]],
  )
}

///|
test "XML mapping rejects XPath unknown options collisions and malformed policy" {
  for
    source in [
      "{}", "[]", "{", "{\"record_path\":[],\"fields\":[]}", "{\"record_path\":[\"r\"],\"fields\":[{\"name\":\"x\",\"path\":[]}],\"typo\":1}",
      "{\"record_path\":[\"r//row\"],\"fields\":[{\"name\":\"x\",\"path\":[]}]}",
      "{\"record_path\":[\"r\"],\"fields\":[{\"name\":\"x\",\"path\":[\"*\"]}]}",
      "{\"record_path\":[\"r\"],\"fields\":[{\"name\":\"x\",\"path\":[\"p:name\"]}]}",
      "{\"record_path\":[\"r\"],\"fields\":[{\"name\":\"x\",\"path\":[],\"repeated\":\"first\"}]}",
      "{\"record_path\":[\"r\"],\"fields\":[{\"name\":\"x\",\"path\":[],\"repeated\":\"join\"}]}",
      "{\"record_path\":[\"r\"],\"fields\":[{\"name\":\"x\",\"path\":[],\"separator\":\";\"}]}",
      "{\"record_path\":[\"r\"],\"fields\":[{\"name\":\"x\",\"path\":[]},{\"name\":\"x\",\"path\":[]}]}",
      "{\"record_path\":[\"r\"],\"fields\":[{\"name\":\" \",\"path\":[]}]}", "{\"record_path\":[\"r\"],\"fields\":[{\"name\":\"x\",\"path\":[],\"attribute\":\"xmlns\"}]}",
    ] {
    assert_true(
      try @jsontable.parse_xml_spec(source) catch {
        _ => true
      } noraise {
        _ => false
      },
    )
  }
}

///|
test "XML record input depth node attribute field and output limits" {
  let spec = record_spec()
  assert_true(
    try @jsontable.parse_xml_records(" ".repeat(1_000_001), spec) catch {
      value => value is XmlRecordLimit(_)
    } noraise {
      _ => false
    },
  )
  assert_true(
    try
      @jsontable.parse_xml_records(
        "<catalog>" + "<n>".repeat(32) + "</n>".repeat(32) + "</catalog>",
        spec,
      )
    catch {
      value => value is InvalidRecordXml(_)
    } noraise {
      _ => false
    },
  )
  assert_true(
    try
      @jsontable.parse_xml_records(
        "<catalog>" + "<item/>".repeat(10_001) + "</catalog>",
        spec,
      )
    catch {
      value => value is XmlRecordLimit(_)
    } noraise {
      _ => false
    },
  )
  assert_true(
    try
      @jsontable.parse_xml_records(
        "<catalog>" + "<x/>".repeat(50_000) + "</catalog>",
        spec,
      )
    catch {
      value => value is InvalidRecordXml(_)
    } noraise {
      _ => false
    },
  )
  let attributes = StringBuilder()
  for i = 0; i < 65; i = i + 1 {
    attributes.write_string(" a\{i}='v'")
  }
  assert_true(
    try
      @jsontable.parse_xml_records(
        "<catalog" + attributes.to_string() + "/>",
        spec,
      )
    catch {
      value => value is InvalidRecordXml(_)
    } noraise {
      _ => false
    },
  )
  assert_true(
    try
      @jsontable.parse_xml_records(
        "<catalog><item><name>" + "x".repeat(65537) + "</name></item></catalog>",
        spec,
      )
    catch {
      value => value is XmlRecordLimit(_)
    } noraise {
      _ => false
    },
  )
  assert_true(
    try @jsontable.parse_xml_spec(" ".repeat(65537)) catch {
      value => value is XmlRecordLimit(_)
    } noraise {
      _ => false
    },
  )
  let field : @jsontable.XmlField = {
    name: "x",
    path: ["name"],
    attribute: None,
    repeated: RejectRepeated,
  }
  let wide : @jsontable.XmlRecordSpec = {
    record_path: ["catalog", "item"],
    fields: Array::makei(128, i => { ..field, name: "f\{i}", }),
  }
  assert_true(
    try
      @jsontable.parse_xml_records(
        "<catalog>" + "<item/>".repeat(781) + "</catalog>",
        wide,
      )
    catch {
      value => value is XmlRecordLimit(_)
    } noraise {
      _ => false
    },
  )
  assert_true(
    try
      @jsontable.parse_xml_records(
        "<catalog><item><name>" + "x".repeat(16000) + "</name></item></catalog>",
        wide,
      )
    catch {
      value => value is XmlRecordLimit(_)
    } noraise {
      _ => false
    },
  )
  let too_many : @jsontable.XmlRecordSpec = {
    ..wide,
    fields: Array::makei(129, i => { ..field, name: "f\{i}", }),
  }
  assert_true(
    try @jsontable.parse_xml_records("<catalog/>", too_many) catch {
      value => value is InvalidXmlSpec(_)
    } noraise {
      _ => false
    },
  )
}

///|
test "XML intake exact limits and long repeated-field separators" {
  let spec = record_spec()
  let table = @jsontable.parse_xml_records(
    "<catalog><item><name>" + "x".repeat(65536) + "</name></item></catalog>",
    spec,
  )
  assert_eq(table.text_rows()[0][1].length(), 65536)
  let empty_rows = @jsontable.parse_xml_records(
    "<catalog>" + "<item/>".repeat(10000) + "</catalog>",
    spec,
  )
  assert_eq(empty_rows.rows.length(), 10000)
  let joined : @jsontable.XmlRecordSpec = {
    record_path: ["r"],
    fields: [
      {
        name: "x",
        path: ["x"],
        attribute: None,
        repeated: JoinRepeated(";".repeat(256)),
      },
    ],
  }
  assert_true(
    try
      @jsontable.parse_xml_records("<r>" + "<x/>".repeat(258) + "</r>", joined)
    catch {
      value => value is XmlRecordLimit(_)
    } noraise {
      _ => false
    },
  )
  let deep : @jsontable.XmlRecordSpec = {
    ..joined,
    record_path: Array::make(17, "r"),
  }
  assert_true(
    try @jsontable.parse_xml_records("<r/>", deep) catch {
      value => value is InvalidXmlSpec(_)
    } noraise {
      _ => false
    },
  )
}

///|
test "XML record text is literal in XLSX even when formula-shaped" {
  let spec = @jsontable.parse_xml_spec(
    "{\"record_path\":[\"r\"],\"fields\":[{\"name\":\"value\",\"path\":[]}]}",
  )
  let table = @jsontable.parse_xml_records(
    "<?xml\tversion='1.0'?><r>=HYPERLINK(&quot;https://example.invalid&quot;)</r>",
    spec,
  )
  let workbook = @xlsx.read(@opc.open(table.export_xlsx()))
  assert_true(
    workbook.sheets[0].cells.any(cell => {
      cell.value == Text("=HYPERLINK(\"https://example.invalid\")")
    }),
  )
  assert_true(
    try
      @jsontable.parse_xml_records("<?xml version='&#49;.0'?><r/>", spec)
    catch {
      value => value is InvalidRecordXml(_)
    } noraise {
      _ => false
    },
  )
}

///|
test "XML record lexical validation handles reference spelling and selector URIs" {
  let spec = @jsontable.parse_xml_spec(
    "{\"record_path\":[\"r\"],\"fields\":[{\"name\":\"x\",\"path\":[]}]}",
  )
  assert_true(
    try @jsontable.parse_xml_records("<r>&#X41;</r>", spec) catch {
      value => value is InvalidRecordXml(_)
    } noraise {
      _ => false
    },
  )
  assert_true(
    try @jsontable.parse_xml_records("<r a='&#X41;'/>", spec) catch {
      value => value is InvalidRecordXml(_)
    } noraise {
      _ => false
    },
  )
  assert_eq(
    @jsontable.parse_xml_records("<r><![CDATA[&#X41;]]></r>", spec).text_rows(),
    [["&#X41;"]],
  )
  let bad : @jsontable.XmlRecordSpec = { ..spec, record_path: ["{urn:a b}r"], }
  assert_true(
    try @jsontable.parse_xml_records("<r/>", bad) catch {
      value => value is InvalidXmlSpec(_)
    } noraise {
      _ => false
    },
  )
}
