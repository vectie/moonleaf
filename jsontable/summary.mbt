///|
/// Numeric measures explicitly parse CSV text; group columns remain exact values.
pub(all) enum SummaryOperation {
  CountRows
  Sum(String)
  Mean(String)
} derive(Debug, Eq)

///|
pub(all) struct SummaryMeasure {
  name : String
  operation : SummaryOperation
} derive(Debug, Eq)

///|
pub(all) suberror SummaryError {
  InvalidSummary(String)
  UnknownSummaryColumn(String)
  InvalidSummaryNumber(row~ : Int, column~ : String)
  SummaryOverflow(row~ : Int, column~ : String)
  UnsupportedGroupValue(row~ : Int, column~ : String)
} derive(Debug, Eq)

///|
priv struct SummaryAccumulator {
  mut count : Int
  mut sum : Double
  mut correction : Double
}

///|
priv struct SummaryGroup {
  keys : Array[@scene.CellValue]
  measures : Array[SummaryAccumulator]
}

///|
fn summary_column(table : Table, name : String) -> Int raise SummaryError {
  for i, column in table.columns {
    if name == column {
      return i
    }
  }
  raise UnknownSummaryColumn(name)
}

///|
fn summary_number(
  value : @scene.CellValue,
  row~ : Int,
  column~ : String,
) -> Double? raise SummaryError {
  let text = match value {
    Empty => return None
    Text(text) | Number(text) => text.trim(chars=" \t\r\n").to_owned()
    _ => raise InvalidSummaryNumber(row~, column~)
  }
  if text == "" {
    return None
  }
  let json = @json.parse(text) catch {
    _ => raise InvalidSummaryNumber(row~, column~)
  }
  guard json is Number(number, ..) && !number.is_inf() && !number.is_nan() else {
    raise InvalidSummaryNumber(row~, column~)
  }
  Some(number)
}

///|
fn summary_key(
  value : @scene.CellValue,
  row~ : Int,
  column~ : String,
) -> Json raise SummaryError {
  // Tags keep missing, empty text, numeric text and booleans distinct. JSON
  // framing avoids collisions when key text itself contains delimiters.
  match value {
    Empty => ["empty"]
    Text(text) => ["text", text]
    Number(_) => {
      let number = summary_number(value, row~, column~)
      guard number is Some(number) else {
        raise UnsupportedGroupValue(row~, column~)
      }
      ["number", if number == 0.0 { "0" } else { number.to_string() }]
    }
    Boolean(flag) => ["boolean", flag]
    _ => raise UnsupportedGroupValue(row~, column~)
  }
}

///|
fn new_summary_group(
  keys : Array[@scene.CellValue],
  count : Int,
) -> SummaryGroup {
  {
    keys,
    measures: Array::makei(count, _ => { count: 0, sum: 0.0, correction: 0.0, }),
  }
}

///|
fn SummaryAccumulator::add(
  self : SummaryAccumulator,
  value : Double,
  row~ : Int,
  column~ : String,
) -> Unit raise SummaryError {
  let total = self.sum + value
  // Neumaier compensated summation retains small contributions to large totals.
  let adjustment = if self.sum.abs() >= value.abs() {
    self.sum - total + value
  } else {
    value - total + self.sum
  }
  let correction = self.correction + adjustment
  let corrected = total + correction
  if corrected.is_inf() || corrected.is_nan() {
    raise SummaryOverflow(row~, column~)
  }
  self.sum = total
  self.correction = correction
  self.count += 1
}

///|
/// Produce a fresh summary table, in first-seen group order. An empty group_by
/// produces one grand-total row, including for an empty input. Numeric measures
/// ignore blank cells and reject all other nonnumeric values. CountRows counts
/// every input row; Sum of no values is zero, Mean of no values is Empty.
pub fn Table::summarize(
  self : Table,
  group_by~ : Array[String],
  measures~ : Array[SummaryMeasure],
) -> Table raise SummaryError {
  validate_lookup_table(self) catch {
    _ =>
      raise InvalidSummary(
        "Expected unique nonempty columns and rectangular rows",
      )
  }
  if self.columns.length() > 256 ||
    self.rows.length() > 10_000 ||
    self.columns.length() * self.rows.length() > 100_000 {
    raise InvalidSummary(
      "Input exceeds 256 columns, 10000 rows or 100000 cells",
    )
  }
  if measures.is_empty() || group_by.length() + measures.length() > 256 {
    raise InvalidSummary(
      "Expected at least one measure and at most 256 output columns",
    )
  }
  let columns : Array[String] = []
  let group_indices : Array[Int] = []
  for column in group_by {
    if columns.contains(column) {
      raise InvalidSummary("Duplicate group column: " + column)
    }
    group_indices.push(summary_column(self, column))
    columns.push(column)
  }
  let measure_indices : Array[Int?] = []
  for measure in measures {
    if measure.name == "" || columns.contains(measure.name) {
      raise InvalidSummary("Empty or duplicate output column: " + measure.name)
    }
    columns.push(measure.name)
    measure_indices.push(
      match measure.operation {
        CountRows => None
        Sum(column) | Mean(column) => Some(summary_column(self, column))
      },
    )
  }
  let groups : Array[SummaryGroup] = []
  let indices : Map[String, Int] = Map::new()
  if group_by.is_empty() {
    groups.push(new_summary_group([], measures.length()))
    indices["[]"] = 0
  }
  for row_index, row in self.rows {
    let keys = group_indices.map(index => row[index])
    let encoded : Array[Json] = []
    for i, key in keys {
      encoded.push(summary_key(key, row=row_index + 1, column=group_by[i]))
    }
    let key = Json::array(encoded).stringify()
    let index = match indices.get(key) {
      Some(index) => index
      None => {
        let index = groups.length()
        if (index + 2) * columns.length() > 100_000 {
          raise InvalidSummary("Summary exceeds 100000 cells including header")
        }
        indices[key] = index
        groups.push(new_summary_group(keys, measures.length()))
        index
      }
    }
    let group = groups[index]
    for i, measure in measures {
      let accumulator = group.measures[i]
      match measure_indices[i] {
        None => accumulator.count += 1
        Some(column) =>
          match
            summary_number(
              row[column],
              row=row_index + 1,
              column=self.columns[column],
            ) {
            None => ()
            Some(number) =>
              accumulator.add(number, row=row_index + 1, column=measure.name)
          }
      }
    }
  }
  let rows = groups.map(group => {
    let row = group.keys.copy()
    for i, measure in measures {
      let accumulator = group.measures[i]
      row.push(
        match measure.operation {
          CountRows => @scene.Number(accumulator.count.to_string())
          Sum(_) =>
            @scene.Number(
              (accumulator.sum + accumulator.correction).to_string(),
            )
          Mean(_) =>
            if accumulator.count == 0 {
              @scene.Empty
            } else {
              @scene.Number(
                ((accumulator.sum + accumulator.correction) /
                accumulator.count.to_double()).to_string(),
              )
            }
        },
      )
    }
    row
  })
  { columns, rows, }
}
