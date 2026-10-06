///|
test "boundary explicit cell row can disagree with implicit container row" {
  review_one_edit(
    review_worksheet(
      (
        #|<worksheet><sheetData><row><c r="A5" t="inlineStr"><is><t>five</t></is></c></row></sheetData></worksheet>
      ),
    ),
    5,
    1,
  )
}

///|
test "boundary descending explicit rows can insert duplicate before existing target" {
  review_one_edit(
    review_worksheet(
      (
        #|<worksheet><sheetData><row r="5"><c r="A5"><v>5</v></c></row><row r="1"><c r="A1" t="inlineStr"><is><t>one</t></is></c></row></sheetData></worksheet>
      ),
    ),
    1,
    1,
  )
}

///|
test "boundary descending explicit columns can insert duplicate before existing target" {
  review_one_edit(
    review_worksheet(
      (
        #|<worksheet><sheetData><row r="1"><c r="C1"><v>3</v></c><c r="A1" t="inlineStr"><is><t>one</t></is></c></row></sheetData></worksheet>
      ),
    ),
    1,
    1,
  )
}
