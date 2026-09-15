///|
fn inspect_fixture(
  workbook_extra : String,
  styles : String?,
  shared_strings : String?,
  cells : String,
) -> @opc.Package {
  let parts = [
    text_part(
      "xl/workbook.xml",
      "<workbook xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\">" +
      workbook_extra +
      "<sheets><sheet name=\"Sheet1\" sheetId=\"1\" r:id=\"rId1\"/></sheets></workbook>",
    ),
    text_part(
      "xl/_rels/workbook.xml.rels",
      "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet1.xml\"/>" +
      (if styles is Some(_) {
        "<Relationship Id=\"rId2\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles\" Target=\"styles.xml\"/>"
      } else {
        ""
      }) +
      (if shared_strings is Some(_) {
        "<Relationship Id=\"rId3\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/sharedStrings\" Target=\"sharedStrings.xml\"/>"
      } else {
        ""
      }) +
      "</Relationships>",
    ),
    text_part(
      "xl/worksheets/sheet1.xml",
      "<worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\"><sheetData><row r=\"1\">" +
      cells +
      "</row></sheetData></worksheet>",
    ),
  ]
  if styles is Some(xml) {
    parts.push(text_part("xl/styles.xml", xml))
  }
  if shared_strings is Some(xml) {
    parts.push(text_part("xl/sharedStrings.xml", xml))
  }
  { parts, }
}

///|
fn relationship_security_fixture(
  metadata_relationships : String,
  metadata_parts : Array[@opc.Part],
  cell : String,
) -> @opc.Package {
  let parts = [
    text_part(
      "xl/workbook.xml", "<workbook xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\"><sheets><sheet name=\"Sheet1\" sheetId=\"1\" r:id=\"rId1\"/></sheets></workbook>",
    ),
    text_part(
      "xl/_rels/workbook.xml.rels",
      "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet1.xml\"/>" +
      metadata_relationships +
      "</Relationships>",
    ),
    text_part(
      "xl/worksheets/sheet1.xml",
      "<worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\"><sheetData><row r=\"1\">" +
      cell +
      "</row></sheetData></worksheet>",
    ),
  ]
  let fixture : @opc.Package = { parts, }
  for part in metadata_parts {
    fixture.parts.push(part)
  }
  fixture
}

///|
fn worksheet_relationship_fixture(
  worksheet_type : String,
  worksheet_target : String,
  worksheet_part : String,
  extra_parts : Array[@opc.Part],
) -> @opc.Package {
  let parts = [
    text_part(
      "xl/workbook.xml", "<workbook xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\"><sheets><sheet name=\"Sheet1\" sheetId=\"1\" r:id=\"rId1\"/></sheets></workbook>",
    ),
    text_part(
      "xl/_rels/workbook.xml.rels",
      "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"" +
      worksheet_type +
      "\" Target=\"" +
      worksheet_target +
      "\"/></Relationships>",
    ),
    text_part(
      worksheet_part, "<worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\"><sheetData><row r=\"1\"><c r=\"A1\"><v>7</v></c></row></sheetData></worksheet>",
    ),
  ]
  for part in extra_parts {
    parts.push(part)
  }
  { parts, }
}

///|
test "inspect rejects suffix worksheet type despite present decoy worksheet" {
  let fixture = worksheet_relationship_fixture(
    "http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet-spoof",
    "worksheets/decoy.xml",
    "xl/worksheets/decoy.xml",
    [],
  )
  ignore(@xlsx.inspect(fixture)) catch {
    @xlsx.XlsxError::MissingWorksheet(_) => return
    _ => fail("expected MissingWorksheet")
  }
  fail("expected MissingWorksheet")
}

///|
test "inspect accepts relocated purl worksheet" {
  let fixture = worksheet_relationship_fixture(
    "http://purl.oclc.org/ooxml/officeDocument/relationships/worksheet",
    "relocated/sheet1.xml",
    "xl/relocated/sheet1.xml",
    [],
  )
  let got = @xlsx.inspect(fixture)
  assert_eq(got.length(), 1)
  assert_true(got[0].raw_value is Some("7"))
}

///|
test "inspect rejects above-root official worksheet target even when part exists" {
  let fixture = worksheet_relationship_fixture(
    "http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet",
    "../../evil.xml",
    "evil.xml",
    [],
  )
  ignore(@xlsx.inspect(fixture)) catch {
    @xlsx.XlsxError::PackageFailure(_) => return
    _ => fail("expected PackageFailure")
  }
  fail("expected PackageFailure")
}

///|
test "inspect rejects duplicate exact internal metadata relationships" {
  let cases = [
    (
      "styles", "<Relationship Id=\"rId2\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles\" Target=\"styles-a.xml\"/><Relationship Id=\"rId3\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles\" Target=\"styles-b.xml\"/>",
    ),
    (
      "shared strings", "<Relationship Id=\"rId2\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/sharedStrings\" Target=\"strings-a.xml\"/><Relationship Id=\"rId3\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/sharedStrings\" Target=\"strings-b.xml\"/>",
    ),
  ]
  for item in cases {
    let (label, relationships) = item
    let fixture = relationship_security_fixture(
      relationships,
      [],
      "<c r=\"A1\"><v>1</v></c>",
    )
    ignore(@xlsx.inspect(fixture)) catch {
      @xlsx.XlsxError::PackageFailure(_) => continue
      _ => fail("expected PackageFailure for " + label)
    }
    fail("expected PackageFailure for " + label)
  }
}

///|
test "inspect accepts relocated purl styles and purl shared strings" {
  let fixture = relationship_security_fixture(
    "<Relationship Id=\"rId2\" Type=\"http://purl.oclc.org/ooxml/officeDocument/relationships/styles\" Target=\"metadata/strict-styles.xml\"/><Relationship Id=\"rId3\" Type=\"http://purl.oclc.org/ooxml/officeDocument/relationships/sharedStrings\" Target=\"metadata/purl-strings.xml\"/>",
    [
      text_part(
        "xl/metadata/strict-styles.xml", "<styleSheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\"><cellXfs count=\"1\"><xf numFmtId=\"14\"/></cellXfs></styleSheet>",
      ),
      text_part(
        "xl/metadata/purl-strings.xml", "<sst xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\"><si><t>relocated purl</t></si></sst>",
      ),
    ],
    "<c r=\"A1\" t=\"s\" s=\"0\"><v>0</v></c>",
  )
  let got = @xlsx.inspect(fixture)
  assert_eq(got.length(), 1)
  assert_true(got[0].resolved_text is Some("relocated purl"))
  assert_true(got[0].number_format is Some("m/d/yy"))
  assert_true(got[0].warnings.is_empty())
}

///|
test "inspect ignores external exact metadata despite local decoys" {
  let fixture = relationship_security_fixture(
    "<Relationship Id=\"rId2\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles\" Target=\"styles.xml\" TargetMode=\"External\"/><Relationship Id=\"rId3\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/sharedStrings\" Target=\"sharedStrings.xml\" TargetMode=\"External\"/>",
    [
      text_part(
        "xl/styles.xml", "<styleSheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\"><cellXfs count=\"1\"><xf numFmtId=\"14\"/></cellXfs></styleSheet>",
      ),
      text_part(
        "xl/sharedStrings.xml", "<sst xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\"><si><t>decoy</t></si></sst>",
      ),
    ],
    "<c r=\"A1\" s=\"0\"><v>1</v></c>",
  )
  let got = @xlsx.inspect(fixture)
  assert_true(got[0].resolved_text is None)
  assert_true(got[0].number_format is None)
  assert_true(got[0].warnings is [@xlsx.MissingStylesPart])
}

///|
test "inspect ignores external sharedStrings despite local decoy" {
  let fixture = relationship_security_fixture(
    "<Relationship Id=\"rId3\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/sharedStrings\" Target=\"sharedStrings.xml\" TargetMode=\"External\"/>",
    [
      text_part(
        "xl/sharedStrings.xml", "<sst xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\"><si><t>decoy</t></si></sst>",
      ),
    ],
    "<c r=\"A1\" t=\"s\"><v>0</v></c>",
  )
  try {
    let _ = @xlsx.inspect(fixture)
    fail("expected InvalidSharedStringIndex")
  } catch {
    @xlsx.InvalidSharedStringIndex(0) => ()
    _ => fail("expected InvalidSharedStringIndex(0)")
  }
}

///|
test "inspect rejects suffix spoof relationship types" {
  let fixture = relationship_security_fixture(
    "<Relationship Id=\"rId2\" Type=\"http://attacker.invalid/styles/http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles\" Target=\"styles.xml\"/><Relationship Id=\"rId3\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/sharedStrings.evil\" Target=\"sharedStrings.xml\"/>",
    [
      text_part(
        "xl/styles.xml", "<styleSheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\"><cellXfs count=\"1\"><xf numFmtId=\"14\"/></cellXfs></styleSheet>",
      ),
      text_part(
        "xl/sharedStrings.xml", "<sst xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\"><si><t>spoof</t></si></sst>",
      ),
    ],
    "<c r=\"A1\" s=\"0\"><v>1</v></c>",
  )
  let got = @xlsx.inspect(fixture)
  assert_true(got[0].resolved_text is None)
  assert_true(got[0].warnings is [@xlsx.MissingStylesPart])
}

///|
test "inspect rejects sharedStrings suffix spoof despite present decoy" {
  let fixture = relationship_security_fixture(
    "<Relationship Id=\"rId2\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/sharedStrings.evil\" Target=\"sharedStrings.xml\"/>",
    [
      text_part(
        "xl/sharedStrings.xml", "<sst xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\"><si><t>decoy</t></si></sst>",
      ),
    ],
    "<c r=\"A1\" t=\"s\"><v>0</v></c>",
  )
  try {
    ignore(@xlsx.inspect(fixture))
    fail("expected InvalidSharedStringIndex")
  } catch {
    @xlsx.InvalidSharedStringIndex(0) => ()
    _ => fail("expected InvalidSharedStringIndex(0)")
  }
}

///|
test "inspect fails closed on above-root exact metadata target" {
  let fixture = relationship_security_fixture(
    "<Relationship Id=\"rId2\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles\" Target=\"../../styles.xml\"/>",
    [],
    "<c r=\"A1\"><v>1</v></c>",
  )
  try {
    ignore(@xlsx.inspect(fixture))
    fail("expected PackageFailure")
  } catch {
    @xlsx.PackageFailure(_) => ()
    _ => fail("expected PackageFailure")
  }
}

///|
test "inspect reports an exact missing styles relationship target" {
  let base = inspect_fixture("", None, None, "<c r=\"A1\" s=\"0\"><v>1</v></c>")
  let fixture : @opc.Package = {
    parts: base.parts.map(fn(part) {
      if part.name == "xl/_rels/workbook.xml.rels" {
        text_part(
          part.name,
          "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet1.xml\"/><Relationship Id=\"rId2\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles\" Target=\"missing-styles.xml\"/></Relationships>",
        )
      } else {
        part
      }
    }),
  }
  let rejected = try @xlsx.inspect(fixture) catch {
    @xlsx.PackageFailure(_) => true
    _ => false
  } noraise {
    _ => false
  }
  assert_true(rejected)
}

///|
test "inspect reports an exact missing sharedStrings relationship target" {
  let base = inspect_fixture("", None, None, "<c r=\"A1\" t=\"s\"><v>0</v></c>")
  let fixture : @opc.Package = {
    parts: base.parts.map(fn(part) {
      if part.name == "xl/_rels/workbook.xml.rels" {
        text_part(
          part.name,
          "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet1.xml\"/><Relationship Id=\"rId2\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/sharedStrings\" Target=\"missing-sharedStrings.xml\"/></Relationships>",
        )
      } else {
        part
      }
    }),
  }
  let rejected = try @xlsx.inspect(fixture) catch {
    @xlsx.PackageFailure(_) => true
    _ => false
  } noraise {
    _ => false
  }
  assert_true(rejected)
}

///|
test "inspect resolves shared inline and formula strings exactly" {
  let fixture = inspect_fixture(
    "",
    None,
    Some(
      "<sst xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\" count=\"2\" uniqueCount=\"2\"><si><t>plain shared</t></si><si><r><t>rich </t></r><r><t>shared</t></r></si></sst>",
    ),
    "<c r=\"A1\" t=\"s\"><v>0</v></c><c r=\"B1\" t=\"s\"><v>1</v></c><c r=\"C1\" t=\"inlineStr\"><is><r><t>inline </t></r><r><t>rich</t></r></is></c><c r=\"D1\" t=\"str\"><f>CONCAT(&quot;raw&quot;,&quot; result&quot;)</f><v>raw result</v></c><c r=\"E1\"><f>1+2</f><v>3</v></c>",
  )
  let got = @xlsx.inspect(fixture)
  assert_eq(got.length(), 5)
  assert_true(got[0].resolved_text is Some("plain shared"))
  assert_true(got[1].resolved_text is Some("rich shared"))
  assert_true(got[2].resolved_text is Some("inline rich"))
  assert_true(got[3].resolved_text is Some("raw result"))
  assert_true(got[3].formula is Some("CONCAT(\"raw\",\" result\")"))
  assert_true(got[3].cached_value is Some("raw result"))
  assert_true(got[4].formula is Some("1+2"))
  assert_true(got[4].cached_value is Some("3"))
  assert_true(got[4].resolved_text is None)
}

///|
test "inspect custom number-format section classification" {
  let styles = "<styleSheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\"><numFmts count=\"4\"><numFmt numFmtId=\"164\" formatCode=\"0 &quot;days&quot;\"/><numFmt numFmtId=\"165\" formatCode=\"0\\d [Red]\"/><numFmt numFmtId=\"166\" formatCode=\"yyyy-mm-dd;yyyy-mm-dd\"/><numFmt numFmtId=\"167\" formatCode=\"yyyy-mm-dd;0\"/></numFmts><cellXfs count=\"4\"><xf numFmtId=\"164\"/><xf numFmtId=\"165\"/><xf numFmtId=\"166\"/><xf numFmtId=\"167\"/></cellXfs></styleSheet>"
  let got = @xlsx.inspect(
    inspect_fixture(
      "",
      Some(styles),
      None,
      "<c r=\"A1\" s=\"0\"><v>2</v></c><c r=\"B1\" s=\"1\"><v>2</v></c><c r=\"C1\" s=\"2\"><v>2</v></c><c r=\"D1\" s=\"3\"><v>2</v></c>",
    ),
  )
  assert_eq(got.length(), 4)
  assert_true(got[0].date_time is None)
  assert_true(got[1].date_time is None)
  assert_true(got[2].date_time is Some(_))
  assert_true(got[3].date_time is None)
  assert_true(got[3].warnings is [AmbiguousNumberFormat(167, "yyyy-mm-dd;0")])
}

///|
test "inspect built-in dates epochs serial-60 rounding and invalid ranges" {
  let styles = "<styleSheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\"><cellXfs count=\"2\"><xf numFmtId=\"0\"/><xf numFmtId=\"14\"/></cellXfs></styleSheet>"
  let got = @xlsx.inspect(
    inspect_fixture(
      "",
      Some(styles),
      None,
      "<c r=\"A1\" s=\"1\"><v>1</v></c><c r=\"B1\" s=\"1\"><v>60</v></c><c r=\"C1\" s=\"1\"><v>2.9999999999</v></c><c r=\"D1\" s=\"1\"><v>-1</v></c><c r=\"E1\" s=\"1\"><v>1e300</v></c>",
    ),
  )
  guard got[0].date_time is Some(first) else { fail("expected date") }
  assert_true(first.year is Some(1900))
  assert_true(first.month is Some(1))
  assert_true(first.day is Some(1))
  guard got[1].date_time is Some(serial60) else { fail("expected serial 60") }
  assert_true(serial60.serial_60)
  guard got[2].date_time is Some(rounded) else { fail("expected rounded date") }
  assert_true(rounded.day is Some(3))
  assert_true(rounded.hour == 0)
  assert_true(got[3].date_time is None)
  assert_true(got[4].date_time is None)
  let epoch = @xlsx.inspect(
    inspect_fixture(
      "<workbookPr date1904=\"1\"/>",
      Some(styles),
      None,
      "<c r=\"A1\" s=\"1\"><v>0</v></c>",
    ),
  )
  guard epoch[0].date_time is Some(date1904) else {
    fail("expected 1904 epoch")
  }
  assert_true(date1904.year is Some(1904))
  assert_true(date1904.month is Some(1))
  assert_true(date1904.day is Some(1))
}

///|
test "numeric date parsing accepts exponents and rejects malformed numbers" {
  let styles = "<styleSheet><cellXfs count=\"1\"><xf numFmtId=\"14\"/></cellXfs></styleSheet>"
  let cells = @xlsx.inspect(
    inspect_fixture(
      "",
      Some(styles),
      None,
      "<c r=\"A1\" s=\"0\"><v>1.25e0</v></c><c r=\"B1\" s=\"0\"><v>1.25days</v></c>",
    ),
  )
  guard cells[0].date_time is Some(date) else {
    fail("exponent date was not parsed")
  }
  assert_eq(date.day, Some(1))
  assert_eq(date.hour, 6)
  assert_eq(cells[1].date_time, None)
}

///|
test "inspect missing and out-of-range styles warn only affected cells" {
  let missing = @xlsx.inspect(
    inspect_fixture(
      "",
      None,
      None,
      "<c r=\"A1\" s=\"1\"><v>1</v></c><c r=\"B1\"><v>2</v></c>",
    ),
  )
  assert_eq(missing[0].warnings.length(), 1)
  assert_eq(missing[1].warnings.length(), 0)
  let styles = "<styleSheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\"><cellXfs count=\"1\"><xf numFmtId=\"0\"/></cellXfs></styleSheet>"
  let ranged = @xlsx.inspect(
    inspect_fixture("", Some(styles), None, "<c r=\"A1\" s=\"9\"><v>1</v></c>"),
  )
  assert_eq(ranged[0].warnings.length(), 1)
}

///|
test "inspect audited custom number-format classifier cases" {
  let codes = [
    "m/mm/mmm", "[h]", "[m]", "[s]", "0_d", "0*d", "yyyy-mm-dd;yyyy-mm-dd;yyyy-mm-dd;@",
    "yyyy-mm-dd;;", "yyyy-mm-dd;0", "yyyy-\"oops", "yyyy-[mm", "yyyy-\\",
  ]
  let expected = [
    @xlsx.Date,
    @xlsx.Time,
    @xlsx.Time,
    @xlsx.Time,
    @xlsx.Number,
    @xlsx.Number,
    @xlsx.Date,
    @xlsx.Date,
    @xlsx.Unsupported,
    @xlsx.Unsupported,
    @xlsx.Unsupported,
    @xlsx.Unsupported,
  ]
  let mut num_fmts = ""
  let mut xfs = ""
  let mut cells = ""
  let refs = [
    "A1", "B1", "C1", "D1", "E1", "F1", "G1", "H1", "I1", "J1", "K1", "L1",
  ]
  for i, code in codes {
    let escaped = code
      .replace(old="&", new="&amp;")
      .replace(old="\"", new="&quot;")
    num_fmts = num_fmts +
      "<numFmt numFmtId=\"" +
      (164 + i).to_string() +
      "\" formatCode=\"" +
      escaped +
      "\"/>"
    xfs = xfs + "<xf numFmtId=\"" + (164 + i).to_string() + "\"/>"
    let r = refs[i]
    cells = cells +
      "<c r=\"" +
      r +
      "\" s=\"" +
      i.to_string() +
      "\"><v>2</v></c>"
  }
  let styles = "<styleSheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\"><numFmts count=\"12\">" +
    num_fmts +
    "</numFmts><cellXfs count=\"12\">" +
    xfs +
    "</cellXfs></styleSheet>"
  let got = @xlsx.inspect(inspect_fixture("", Some(styles), None, cells))
  assert_eq(got.length(), expected.length())
  for i, want in expected {
    assert_true(got[i].display_kind == want)
    if want == @xlsx.Unsupported {
      assert_eq(got[i].warnings.length(), 1)
    }
  }
}

///|
test "inspect Excel date upper bounds and rounding carry for both epochs" {
  let styles = "<styleSheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\"><cellXfs count=\"1\"><xf numFmtId=\"14\"/></cellXfs></styleSheet>"
  let cells1900 = "<c r=\"A1\" s=\"0\"><v>2958465</v></c><c r=\"B1\" s=\"0\"><v>2958466</v></c><c r=\"C1\" s=\"0\"><v>2958464.9999999999</v></c><c r=\"D1\" s=\"0\"><v>2958465.9999999999</v></c>"
  let got1900 = @xlsx.inspect(
    inspect_fixture("", Some(styles), None, cells1900),
  )
  guard got1900[0].date_time is Some(max1900) else {
    fail("expected 1900 maximum")
  }
  assert_true(max1900.year is Some(9999))
  assert_true(max1900.month is Some(12))
  assert_true(max1900.day is Some(31))
  assert_true(got1900[1].date_time is None)
  guard got1900[2].date_time is Some(carried1900) else {
    fail("expected 1900 carry")
  }
  assert_true(carried1900.year is Some(9999))
  assert_true(carried1900.month is Some(12))
  assert_true(carried1900.day is Some(31))
  assert_true(carried1900.hour == 0)
  assert_true(carried1900.minute == 0)
  assert_true(carried1900.second == 0)
  assert_true(got1900[3].date_time is None)

  let cells1904 = "<c r=\"A1\" s=\"0\"><v>2957003</v></c><c r=\"B1\" s=\"0\"><v>2957004</v></c><c r=\"C1\" s=\"0\"><v>2957002.9999999999</v></c><c r=\"D1\" s=\"0\"><v>2957003.9999999999</v></c>"
  let got1904 = @xlsx.inspect(
    inspect_fixture(
      "<workbookPr date1904=\"1\"/>",
      Some(styles),
      None,
      cells1904,
    ),
  )
  guard got1904[0].date_time is Some(max1904) else {
    fail("expected 1904 maximum")
  }
  assert_true(max1904.year is Some(9999))
  assert_true(max1904.month is Some(12))
  assert_true(max1904.day is Some(31))
  assert_true(got1904[1].date_time is None)
  guard got1904[2].date_time is Some(carried1904) else {
    fail("expected 1904 carry")
  }
  assert_true(carried1904.year is Some(9999))
  assert_true(carried1904.month is Some(12))
  assert_true(carried1904.day is Some(31))
  assert_true(carried1904.hour == 0)
  assert_true(carried1904.minute == 0)
  assert_true(carried1904.second == 0)
  assert_true(got1904[3].date_time is None)
}
