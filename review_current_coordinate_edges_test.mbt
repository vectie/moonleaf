///|
test "independent duplicate target cannot bypass refusal through same value fast path" {
  let bytes = review_worksheet(
    (
      #|<worksheet><sheetData><row><c r="A1" t="inlineStr"><is><t>one</t></is></c><c r="A01" t="inlineStr"><is><t>other</t></is></c></row></sheetData></worksheet>
    ),
  )
  let original = @moonleaf.open_session("duplicate-noop.xlsx", bytes)
  let before = original.scene()
  let saved = original.save_as_copy().bytes()
  let rejections = []
  for text in ["one", "other"] {
    let rejected = try {
      ignore(original.set_cell_text("Sheet1", 1, 1, text))
      false
    } catch {
      @moonleaf.DocumentSessionError::Render(message) =>
        message.contains("duplicate target cell: A1")
      _ => false
    }
    assert_true(original.scene() == before)
    assert_eq(original.save_as_copy().bytes(), saved)
    assert_eq(original.revision(), 0)
    assert_false(original.is_dirty())
    rejections.push(rejected)
  }
  debug_inspect(rejections, content="[true, true]")
}

///|
test "independent raw setters reject aliased duplicate target without changing archive" {
  let bytes = review_worksheet(
    (
      #|<worksheet><sheetData><row><c r="A1" t="inlineStr"><is><t>one</t></is></c><c r="A01" t="inlineStr"><is><t>other</t></is></c><c r="C3"><v>3</v></c></row></sheetData></worksheet>
    ),
  )
  let original = @opc.open(bytes)
  let saved = @opc.save(original)
  try @xlsx.set_cell_text(original, "Sheet1", 1, 1, "one") catch {
    @xlsx.InvalidWorkbook(message) =>
      assert_true(message.contains("duplicate target cell: A1"))
    _ => fail("unexpected text error")
  } noraise {
    _ => fail("ambiguous raw text target accepted")
  }
  try @xlsx.set_cell_number(original, "Sheet1", 1, 1, 1.0) catch {
    @xlsx.InvalidWorkbook(message) =>
      assert_true(message.contains("duplicate target cell: A1"))
    _ => fail("unexpected numeric error")
  } noraise {
    _ => fail("ambiguous numeric target accepted")
  }
  assert_eq(@opc.save(original), saved)
  review_one_edit(bytes, 3, 3)
}

///|
test "independent numeric edit resolves noncanonical explicit row and preserves formula cache" {
  let bytes = review_worksheet(
    (
      #|<worksheet><sheetData><row><c r="A05" s="7"><v>5</v></c><c r="C9" s="9"><f>A5*2</f><v>999</v></c></row><row r="2"><c r="A2" t="inlineStr"><is><t>two</t></is></c></row></sheetData></worksheet>
    ),
  )
  let original = @opc.open(bytes)
  let before = @xlsx.inspect(original)
  let changed = @xlsx.set_cell_number(original, "Sheet1", 5, 1, 9.5)
  let edited = @xlsx.inspect(changed)
  assert_eq(edited.length(), 3)
  assert_eq(edited[0].raw_value, Some("9.5"))
  assert_eq(edited[0].style_id, Some(7))
  assert_eq(edited[1], before[1])
  assert_eq(edited[2], before[2])
  let saved = @opc.save(@xlsx.recalculate(changed))
  let after = @xlsx.inspect(@opc.open(saved))
  assert_eq(after[1].cached_value, Some("19"))
  assert_eq(after[1].style_id, Some(9))
  assert_eq(after[1].formula, Some("A5*2"))
  assert_eq(after[2], before[2])
  assert_true(@xlsx.inspect(original) == before)
  review_unchanged_parts(bytes, saved)
}

///|
test "independent 96 unsorted mismatched layouts preserve every unique coordinate" {
  let orders = [
    [1, 5, 3],
    [1, 3, 5],
    [5, 1, 3],
    [5, 3, 1],
    [3, 1, 5],
    [3, 5, 1],
  ]
  for order in orders {
    for mask in 0..<8 {
      for reverse in [false, true] {
        let xml = StringBuilder()
        xml.write_string("<worksheet><sheetData>")
        for index, anchor in order {
          xml.write_string(
            if (mask & (1 << index)) != 0 {
              "<row r=\"\{anchor}\">"
            } else {
              "<row>"
            },
          )
          let first = if reverse { "C" } else { "A" }
          let last = if reverse { "A" } else { "C" }
          xml.write_string(
            "<c r=\"\{first}\{anchor + 1}\" s=\"7\" t=\"inlineStr\"><is><t>explicit \{index}</t></is></c>",
          )
          xml.write_string(
            "<c s=\"8\" t=\"inlineStr\"><is><t>implicit \{index}</t></is></c>",
          )
          xml.write_string(
            "<c r=\"\{last}\{anchor + 1}\" s=\"9\"><f>A1+1</f><v>999</v></c></row>",
          )
        }
        xml.write_string("</sheetData></worksheet>")
        let bytes = review_worksheet(xml.to_string())
        let original = @moonleaf.open_session("unsorted.xlsx", bytes)
        let before = review_cells(original)
        assert_eq(before.length(), 9)
        for cell in before {
          if cell.value is Text(_) &&
            before
            .filter(c => c.row == cell.row && c.column == cell.column)
            .length() ==
            1 {
            review_one_edit(bytes, cell.row, cell.column)
          }
        }
        let inserted = original
          .set_cell_text("Sheet1", 1, 10, "new J1")
          .set_cell_text("Sheet1", 10, 2, "new B10")
        let saved = inserted.save_as_copy()
        let reopened = @moonleaf.open_session("unsorted.xlsx", saved.bytes())
        let after = review_cells(reopened)
        assert_eq(after.length(), 11)
        assert_true(
          after.filter(c => {
            !(c.row == 1 && c.column == 10) && !(c.row == 10 && c.column == 2)
          }) ==
          before,
        )
        assert_true(scene_cell_is_text(reopened.scene(), 1, 10, "new J1"))
        assert_true(scene_cell_is_text(reopened.scene(), 10, 2, "new B10"))
        assert_true(review_cells(original) == before)
        review_unchanged_parts(bytes, saved.bytes())
      }
    }
  }
}
