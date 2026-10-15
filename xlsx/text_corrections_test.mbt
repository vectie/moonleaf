///|
fn correction_fixture() -> @opc.Package raise {
  @opc.open(
    @xlsx.create(
      [
        [Text("001"), Text("Ada"), Number("12.50")],
        [Text("002"), Text("Bo"), Text("literal")],
      ],
      sheet_name="Contacts",
    ),
  )
}

///|
fn correction(
  address : String,
  expected : String,
  replacement : String,
) -> @xlsx.TextCellCorrection {
  { sheet: "Contacts", address, expected, replacement, }
}

///|
test "text correction applies an exact batch and retains original and non-target values" {
  let original = correction_fixture()
  let before = @opc.save(original)
  let edits = [
    correction("B1", "Ada", "Ada Lovelace"),
    correction("B2", "Bo", "雪😀 & <\r\nnew\tline"),
    correction("C2", "literal", "=SUM(1,2)"),
  ]
  let result = @xlsx.correct_text_cells(original, edits)
  let reopened = @opc.open(@opc.save(result))
  for edit in edits {
    assert_eq(
      @xlsx.inspect_text_cell(
        reopened,
        sheet_name=edit.sheet,
        address=edit.address,
      ).text,
      edit.replacement,
    )
  }
  assert_eq(@xlsx.compare_workbooks(original, reopened).changed_cells, 3)
  assert_eq(
    @xlsx.read_range(reopened, sheet_name="Contacts", range="A1:C1").rows[0],
    [Text("001"), Text("Ada Lovelace"), Number("12.50")],
  )
  assert_eq(@opc.save(original), before)
  for part in original.parts {
    if part.name != "xl/worksheets/sheet1.xml" {
      assert_eq(reopened.part(part.name).unwrap().content, part.content)
    }
  }
}

///|
test "text correction validates every original expectation before returning and checks noops" {
  let original = correction_fixture()
  let bytes = @opc.save(original)
  assert_true(
    try
      @xlsx.correct_text_cells(original, [
        correction("B1", "Ada", "changed"),
        correction("B2", "stale", "replacement"),
      ])
    catch {
      _ => true
    } noraise {
      _ => false
    },
  )
  assert_true(
    try
      @xlsx.correct_text_cells(original, [correction("B1", "stale", "stale")])
    catch {
      _ => true
    } noraise {
      _ => false
    },
  )
  assert_true(
    try
      @xlsx.correct_text_cells(original, [
        correction("B1", "Ada", "changed"),
        correction("B1", "changed", "again"),
      ])
    catch {
      _ => true
    } noraise {
      _ => false
    },
  )
  assert_eq(
    @xlsx.correct_text_cells(original, [correction("B1", "Ada", "Ada")]),
    original,
  )
  assert_eq(@opc.save(original), bytes)
}

///|
test "text correction refuses numbers absent cells noncanonical coordinates and duplicate identities" {
  let original = correction_fixture()
  for address in ["C1", "D1", "B01", "b1", "B0", "XFE1", "B1:B2"] {
    assert_true(
      try
        @xlsx.inspect_text_cell(original, sheet_name="Contacts", address~)
      catch {
        _ => true
      } noraise {
        _ => false
      },
    )
  }
  let xml = original.text("xl/worksheets/sheet1.xml")
  let duplicated = original.replace_text(
    "xl/worksheets/sheet1.xml",
    xml.replace(
      old="</row>",
      new="<c r=\"B1\" t=\"inlineStr\"><is><t>Ada</t></is></c></row>",
    ),
  )
  assert_true(
    try
      @xlsx.inspect_text_cell(duplicated, sheet_name="Contacts", address="B1")
    catch {
      _ => true
    } noraise {
      _ => false
    },
  )
  assert_true(
    try
      @xlsx.inspect_text_cell(original, sheet_name="contacts", address="B1")
    catch {
      _ => true
    } noraise {
      _ => false
    },
  )
}

///|
test "text correction refuses formulas merged anchors and formula result ranges" {
  let original = correction_fixture()
  let xml = original.text("xl/worksheets/sheet1.xml")
  for
    suffix in [
      "<mergeCells><mergeCell ref=\"B1:C1\"/></mergeCells>", "<mergeCells><mergeCell ref=\"A1:B1\"/></mergeCells>",
    ] {
    let merged = original.replace_text(
      "xl/worksheets/sheet1.xml",
      xml.replace(old="</worksheet>", new=suffix + "</worksheet>"),
    )
    assert_true(
      try
        @xlsx.inspect_text_cell(merged, sheet_name="Contacts", address="B1")
      catch {
        _ => true
      } noraise {
        _ => false
      },
    )
  }
  let formula = original.replace_text(
    "xl/worksheets/sheet1.xml",
    xml.replace(
      old="<v>12.50</v>",
      new="<f t=\"array\" ref=\"B1:C1\">1</f><v>12.50</v>",
    ),
  )
  assert_true(
    try
      @xlsx.inspect_text_cell(formula, sheet_name="Contacts", address="B1")
    catch {
      _ => true
    } noraise {
      _ => false
    },
  )
  assert_true(
    try
      @xlsx.inspect_text_cell(formula, sheet_name="Contacts", address="C1")
    catch {
      _ => true
    } noraise {
      _ => false
    },
  )
}

///|
test "text correction refuses rich text metadata and rebound namespaces" {
  let original = correction_fixture()
  let xml = original.text("xl/worksheets/sheet1.xml")
  let bad = [
    xml.replace(
      old="<is><t xml:space=\"preserve\">Ada</t></is>",
      new="<is><r><rPr><b/></rPr><t>Ada</t></r></is>",
    ),
    xml.replace(old="r=\"B1\"", new="r=\"B1\" cm=\"1\""),
    xml.replace(old="<sheetData>", new="<sheetData xmlns=\"urn:other\">"),
  ]
  for value in bad {
    assert_true(value != xml)
    let archive = original.replace_text("xl/worksheets/sheet1.xml", value)
    assert_true(
      try
        @xlsx.inspect_text_cell(archive, sheet_name="Contacts", address="B1")
      catch {
        _ => true
      } noraise {
        _ => false
      },
    )
  }
}

///|
test "text correction accepts exact string boundaries and rejects escaped control oversized text and batch" {
  let original = correction_fixture()
  let max = String::make(32767, 'x')
  let changed = @xlsx.correct_text_cells(original, [
    correction("B1", "Ada", max),
  ])
  assert_eq(
    @xlsx.inspect_text_cell(changed, sheet_name="Contacts", address="B1").text.length(),
    32767,
  )
  for
    value in [String::make(32768, 'x'), "bad\u0001", "_x0041_", "_x005F_x0041_"] {
    assert_true(
      try
        @xlsx.correct_text_cells(original, [correction("B1", "Ada", value)])
      catch {
        _ => true
      } noraise {
        _ => false
      },
    )
  }
  assert_true(
    try @xlsx.correct_text_cells(original, []) catch {
      _ => true
    } noraise {
      _ => false
    },
  )
  assert_true(
    try
      @xlsx.correct_text_cells(
        original,
        Array::make(101, correction("B1", "Ada", "Ada")),
      )
    catch {
      _ => true
    } noraise {
      _ => false
    },
  )
  let empty = @xlsx.correct_text_cells(original, [correction("B1", "Ada", "")])
  assert_eq(
    @xlsx.inspect_text_cell(empty, sheet_name="Contacts", address="B1").text,
    "",
  )
}

///|
test "text correction accepts 100 distinct original targets and retains style identifiers" {
  let original = @opc.open(
    @xlsx.create(Array::make(100, [Text("old")]), sheet_name="Contacts"),
  )
  let styled = original
  let edits = Array::makei(100, i => {
    correction("A" + (i + 1).to_string(), "old", "new")
  })
  let changed = @xlsx.correct_text_cells(styled, edits)
  assert_eq(@xlsx.compare_workbooks(styled, changed).changed_cells, 100)
  assert_eq(
    @xlsx.inspect_text_cell(changed, sheet_name="Contacts", address="A1").style_id,
    Some(1),
  )
  assert_eq(
    @xlsx.inspect_text_cell(changed, sheet_name="Contacts", address="A100").text,
    "new",
  )
}

///|
test "text correction serializes CRLF and standalone CR as references without changing literal entities" {
  let original = correction_fixture()
  let edits = [
    correction("B1", "Ada", "before\r\nafter"),
    correction("B2", "Bo", "before\rafter"),
    correction("C2", "literal", "literal &#13; remains literal"),
  ]
  let changed = @xlsx.correct_text_cells(original, edits)
  let xml = changed.text("xl/worksheets/sheet1.xml")
  assert_false(xml.contains("\r"))
  assert_true(xml.contains("before&#13;\nafter"))
  assert_true(xml.contains("before&#13;after"))
  assert_true(xml.contains("literal &amp;#13; remains literal"))
  let reopened = @opc.open(@opc.save(changed))
  for edit in edits {
    assert_eq(
      @xlsx.inspect_text_cell(
        reopened,
        sheet_name=edit.sheet,
        address=edit.address,
      ).text,
      edit.replacement,
    )
  }
}
