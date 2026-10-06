///|
fn review_worksheet(xml : String) -> FixedArray[Byte] raise {
  @opc.save(
    @opc.open(document_session_xlsx_fixture()).replace_text(
      "xl/worksheets/sheet1.xml", xml,
    ),
  )
}

///|
fn review_cells(
  session : @moonleaf.DocumentSession,
) -> Array[@scene.Cell] raise {
  guard session.scene() is WorkbookDocument({ sheets: [sheet], .. }) else {
    fail("expected one worksheet")
  }
  sheet.cells
}

///|
fn review_unchanged_parts(
  before : FixedArray[Byte],
  after : FixedArray[Byte],
) -> Unit raise {
  let source = @opc.open(before)
  let saved = @opc.open(after)
  assert_eq(source.parts.length(), saved.parts.length())
  for part in source.parts {
    if part.name != "xl/worksheets/sheet1.xml" {
      assert_eq(saved.part(part.name).unwrap().content, part.content)
    }
  }
}

///|
fn review_one_edit(
  bytes : FixedArray[Byte],
  row : Int,
  column : Int,
) -> Unit raise {
  let original = @moonleaf.open_session("review.xlsx", bytes)
  let before = review_cells(original)
  assert_eq(before.filter(c => c.row == row && c.column == column).length(), 1)
  let changed = original.set_cell_text("Sheet1", row, column, "new & < > 🌓")
  let saved = changed.save_as_copy()
  let after = review_cells(@moonleaf.open_session("review.xlsx", saved.bytes()))
  let expected = before.map(c => {
    if c.row == row && c.column == column {
      { ..c, value: @scene.CellValue::Text("new & < > 🌓"), }
    } else {
      c
    }
  })
  assert_eq(after.length(), before.length())
  assert_true(after == expected)
  assert_true(review_cells(original) == before)
  review_unchanged_parts(bytes, saved.bytes())
}

///|
test "review ordered implicit rows survive eight edit save reopen cycles" {
  let bytes = review_worksheet(
    (
      #|<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>
      #|<row><c t="inlineStr" s="4"><is><t>before</t></is></c><c><f>A1</f><v>42</v></c></row>
      #|<row r="5"/><row hidden="1"><c r="A6" t="inlineStr" s="8"><is><t>sixth</t></is></c><c r="C6"><v>7</v></c><c><f>C6+1</f><v>8</v></c></row>
      #|<row><c t="inlineStr"><is><t>neighbor</t></is></c></row></sheetData></worksheet>
    ),
  )
  let original = @moonleaf.open_session("review.xlsx", bytes)
  let before = review_cells(original)
  let mut current = original
  for index in 0..<8 {
    let value = "\{index}: & < > \" ' 🌓\n tail "
    let edited = current.set_cell_text("Sheet1", 6, 1, value)
    assert_eq(edited.revision(), current.revision() + 1)
    let no_op = edited.set_cell_text("Sheet1", 6, 1, value)
    assert_eq(no_op.revision(), edited.revision())
    let saved = no_op.save_as_copy()
    assert_false(saved.session().is_dirty())
    current = @moonleaf.open_session("review.xlsx", saved.bytes())
    assert_false(current.is_dirty())
    assert_eq(current.revision(), 0)
    let expected = before.map(c => {
      if c.row == 6 && c.column == 1 {
        { ..c, value: @scene.CellValue::Text(value), }
      } else {
        c
      }
    })
    assert_true(review_cells(current) == expected)
    review_unchanged_parts(bytes, saved.bytes())
  }
  assert_true(review_cells(original) == before)
}

///|
test "review empty implicit rows and non row children advance only logical rows" {
  let bytes = review_worksheet(
    (
      #|<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:x="urn:review"><sheetData>
      #|<row/><x:keep marker="between"/><row><c t="inlineStr"><is><t>second</t></is></c></row>
      #|<row r="4"/><row customHeight="1"><x:keep marker="row"/><c t="inlineStr" s="7"><is><t>fifth</t></is></c><c r="C5"><f>A5</f><v>5</v></c><c t="inlineStr"><is><t>fourth column</t></is></c></row>
      #|<row><c t="inlineStr"><is><t>sixth</t></is></c></row></sheetData><x:keep marker="after"/></worksheet>
    ),
  )
  review_one_edit(bytes, 2, 1)
  review_one_edit(bytes, 5, 1)
  review_one_edit(bytes, 5, 4)
  let original = @moonleaf.open_session("review.xlsx", bytes)
  let saved = original
    .set_cell_text("Sheet1", 1, 2, "empty first")
    .save_as_copy()
  let xml = @opc.open(saved.bytes()).text("xl/worksheets/sheet1.xml")
  assert_true(xml.contains("marker=\"between\""))
  assert_true(xml.contains("marker=\"row\""))
  assert_true(xml.contains("marker=\"after\""))
  let after = review_cells(saved.session())
  assert_eq(after.length(), review_cells(original).length() + 1)
  for c in review_cells(original) {
    assert_true(
      after.filter(other => other.row == c.row && other.column == c.column) ==
      [c],
    )
  }
}

///|
test "review invalid row attributes use the same fallback already accepted by reader" {
  let bytes = review_worksheet(
    (
      #|<worksheet><sheetData><row r="4"><c><v>4</v></c></row>
      #|<row r=""><c t="inlineStr"><is><t>five</t></is></c></row>
      #|<row r="+6"><c t="inlineStr"><is><t>six</t></is></c></row>
      #|<row r="1048577"><c t="inlineStr"><is><t>seven</t></is></c></row>
      #|<row><c><f>A5</f><v>5</v></c></row></sheetData></worksheet>
    ),
  )
  review_one_edit(bytes, 5, 1)
  review_one_edit(bytes, 6, 1)
  review_one_edit(bytes, 7, 1)
}

///|
test "review prefixed XML stays stable under reader without Office conformance claim" {
  review_one_edit(
    review_worksheet(
      (
        #|<x:worksheet xmlns:x="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><x:sheetData>
        #|<x:row r="9"><x:c r="A9"><x:v>9</x:v></x:c></x:row>
        #|<x:row><x:c s="2" t="inlineStr"><x:is><x:t>ten</x:t></x:is></x:c><x:c r="C10"><x:f>A9</x:f><x:v>9</x:v></x:c></x:row>
        #|</x:sheetData></x:worksheet>
      ),
    ),
    10,
    1,
  )
}

///|
test "review final valid implicit row is editable without shifting upper bound" {
  review_one_edit(
    review_worksheet(
      (
        #|<worksheet><sheetData><row r="1048575"><c><v>1</v></c></row>
        #|<row><c t="inlineStr"><is><t>last row</t></is></c><c r="XFD1048576"><f>A1048575</f><v>1</v></c></row></sheetData></worksheet>
      ),
    ),
    1048576,
    1,
  )
}

///|
test "review repeated edits across inserted gaps preserve later implicit rows" {
  let bytes = review_worksheet(
    (
      #|<worksheet><sheetData><row><c t="inlineStr"><is><t>one</t></is></c></row>
      #|<row r="7"><c t="inlineStr"><is><t>seven</t></is></c></row>
      #|<row><c t="inlineStr"><is><t>eight</t></is></c><c r="D8"><v>4</v></c><c><f>D8+1</f><v>5</v></c></row>
      #|<row><c t="inlineStr"><is><t>nine</t></is></c></row></sheetData></worksheet>
    ),
  )
  let original = @moonleaf.open_session("review.xlsx", bytes)
  let before = review_cells(original)
  let changed = original
    .set_cell_text("Sheet1", 3, 1, "three")
    .set_cell_text("Sheet1", 2, 1, "two")
    .set_cell_text("Sheet1", 8, 2, "B8")
    .set_cell_text("Sheet1", 8, 3, "C8")
    .set_cell_text("Sheet1", 10, 1, "ten")
  let saved = changed.save_as_copy()
  let reopened = @moonleaf.open_session("review.xlsx", saved.bytes())
  let after = review_cells(reopened)
  assert_eq(after.length(), before.length() + 5)
  for c in before {
    assert_true(
      after.filter(other => other.row == c.row && other.column == c.column) ==
      [c],
    )
  }
  let changed_again = reopened.set_cell_text("Sheet1", 8, 3, "C8 twice")
  let second = changed_again.save_as_copy()
  assert_eq(review_cells(second.session()).length(), after.length())
  review_unchanged_parts(bytes, second.bytes())
}

///|
test "review 128 ordered row and cell coordinate mixtures preserve every neighbor" {
  for row_mask in 0..<16 {
    for column_mask in 0..<8 {
      let xml = StringBuilder()
      xml.write_string("<worksheet><sheetData>")
      let positions : Array[(Int, Int)] = []
      let mut previous_row = 0
      for row_index in 0..<4 {
        let explicit_row = (row_mask & (1 << row_index)) != 0
        let row = if explicit_row {
          [1, 3, 4, 7][row_index]
        } else {
          previous_row + 1
        }
        previous_row = row
        xml.write_string(
          if explicit_row {
            "<row r=\"\{row}\">"
          } else {
            "<row>"
          },
        )
        let mut previous_column = 0
        for column_index in 0..<3 {
          let explicit_column = (column_mask & (1 << column_index)) != 0
          let column = if explicit_column {
            [1, 3, 4][column_index]
          } else {
            previous_column + 1
          }
          previous_column = column
          let name = ["A", "B", "C", "D"][column - 1]
          let ref_attr = if explicit_column {
            " r=\"\{name}\{row}\""
          } else {
            ""
          }
          if column_index == 2 {
            xml.write_string(
              "<c\{ref_attr} s=\"9\"><f>A\{row}+1</f><v>101</v></c>",
            )
          } else {
            xml.write_string(
              "<c\{ref_attr} s=\"7\" t=\"inlineStr\"><is><t>value \{row} \{column}</t></is></c>",
            )
            if column_index == 1 {
              positions.push((row, column))
            }
          }
        }
        xml.write_string("</row>")
      }
      xml.write_string("</sheetData></worksheet>")
      let bytes = review_worksheet(xml.to_string())
      let original = @moonleaf.open_session("matrix.xlsx", bytes)
      let mut current = original
      assert_eq(review_cells(original).length(), 12)
      for position in positions {
        let (row, column) = position
        let before = review_cells(current)
        let text = "edited \{row_mask} \{column_mask} \{row} \{column}"
        let saved = current
          .set_cell_text("Sheet1", row, column, text)
          .save_as_copy()
        current = @moonleaf.open_session("matrix.xlsx", saved.bytes())
        let expected = before.map(c => {
          if c.row == row && c.column == column {
            { ..c, value: @scene.CellValue::Text(text), }
          } else {
            c
          }
        })
        assert_true(review_cells(current) == expected)
        review_unchanged_parts(bytes, saved.bytes())
      }
      assert_eq(original.revision(), 0)
      assert_false(original.is_dirty())
    }
  }
}
