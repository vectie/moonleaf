///|
/// A deliberately bounded quote-template formula profile, not an Excel emulator.
priv struct FormulaParser {
  source : String
  mut position : Int
  resolve : (String) -> Double raise XlsxError
  aggregate_resolve : (String) -> Double? raise XlsxError
}

///|
fn formula_finite(value : Double) -> Double raise XlsxError {
  if value.is_nan() || value.is_inf() {
    raise InvalidWorkbook("formula produced a non-finite result")
  }
  value
}

///|
fn FormulaParser::skip(self : FormulaParser) -> Unit {
  while self.position < self.source.length() &&
        self.source[self.position] == ' ' {
    self.position += 1
  }
}

///|
fn FormulaParser::take(self : FormulaParser, code : UInt16) -> Bool {
  self.skip()
  if self.position < self.source.length() && self.source[self.position] == code {
    self.position += 1
    true
  } else {
    false
  }
}

///|
fn FormulaParser::expression(
  self : FormulaParser,
  depth : Int,
) -> Double raise XlsxError {
  if depth > 64 {
    raise InvalidWorkbook("formula nesting bound exceeded")
  }
  let mut value = self.product(depth + 1)
  while true {
    if self.take('+') {
      value += self.product(depth + 1)
    } else if self.take('-') {
      value -= self.product(depth + 1)
    } else {
      break
    }
    value = formula_finite(value)
  }
  value
}

///|
fn FormulaParser::product(
  self : FormulaParser,
  depth : Int,
) -> Double raise XlsxError {
  let mut value = self.power(depth + 1)
  while true {
    if self.take('*') {
      value *= self.power(depth + 1)
    } else if self.take('/') {
      let divisor = self.power(depth + 1)
      if divisor == 0.0 {
        raise InvalidWorkbook("formula division by zero")
      }
      value /= divisor
    } else {
      break
    }
    value = formula_finite(value)
  }
  value
}

///|
fn FormulaParser::power(
  self : FormulaParser,
  depth : Int,
) -> Double raise XlsxError {
  if depth > 64 {
    raise InvalidWorkbook("formula nesting bound exceeded")
  }
  // Excel negation/percent bind before power; equal-precedence powers are
  // evaluated left to right. Parentheses express other intended grouping.
  let mut value = self.atom(depth + 1)
  while self.take('^') {
    value = formula_power(value, self.atom(depth + 1))
  }
  value
}

///|
fn formula_power(base : Double, exponent : Double) -> Double raise XlsxError {
  if base < 0.0 && exponent.trunc() != exponent {
    raise InvalidWorkbook(
      "fractional powers of negative bases are not real numbers",
    )
  }
  if base == 0.0 && exponent <= 0.0 {
    raise InvalidWorkbook("zero base requires a positive exponent")
  }
  formula_finite(@math.pow(base, exponent))
}

///|
fn FormulaParser::token(self : FormulaParser) -> String {
  self.skip()
  let start = self.position
  while self.position < self.source.length() {
    let c = self.source[self.position]
    if (c >= 'A' && c <= 'Z') ||
      (c >= 'a' && c <= 'z') ||
      (c >= '0' && c <= '9') ||
      c == '$' ||
      c == '.' {
      self.position += 1
    } else {
      break
    }
  }
  self.source[start:self.position].to_owned()
}

///|
fn FormulaParser::atom(
  self : FormulaParser,
  depth : Int,
) -> Double raise XlsxError {
  if depth > 64 {
    raise InvalidWorkbook("formula nesting bound exceeded")
  }
  if self.take('+') {
    return self.atom(depth + 1)
  }
  if self.take('-') {
    return -self.atom(depth + 1)
  }
  let value = if self.take('(') {
    let value = self.expression(depth + 1)
    if !self.take(')') {
      raise InvalidWorkbook("formula missing closing parenthesis")
    }
    value
  } else {
    let token = self.token().to_upper()
    if token == "" {
      raise InvalidWorkbook("unsupported formula token")
    }
    if self.take('(') {
      if !["SUM", "ROUND", "MIN", "MAX", "AVERAGE", "COUNT", "POWER"].contains(
          token,
        ) {
        raise InvalidWorkbook("unsupported formula function: " + token)
      }
      let arguments : Array[Double] = []
      while true {
        // Ranges are accepted only as a complete aggregate argument.
        let saved = self.position
        let first = self.token().replace_all(old="$", new="").to_upper()
        if self.take(':') {
          let last = self.token().replace_all(old="$", new="").to_upper()
          guard parse_cell_reference(first) is Some((r1, c1)) &&
            parse_cell_reference(last) is Some((r2, c2)) &&
            r1 <= r2 &&
            c1 <= c2 else {
            raise InvalidWorkbook("invalid formula range")
          }
          if token == "ROUND" ||
            token == "POWER" ||
            (r2 - r1 + 1).to_int64() * (c2 - c1 + 1).to_int64() > 10000L {
            raise InvalidWorkbook("unsupported or oversized formula range")
          }
          for row in r1..<=r2 {
            for column in c1..<=c2 {
              let reference = cell_reference(row, column)
              if token == "AVERAGE" || token == "COUNT" {
                if (self.aggregate_resolve)(reference) is Some(value) {
                  arguments.push(value)
                }
              } else {
                arguments.push((self.resolve)(reference))
              }
            }
          }
        } else {
          self.skip()
          if (token == "AVERAGE" || token == "COUNT") &&
            parse_cell_reference(first) is Some((row, column)) &&
            self.position < self.source.length() &&
            (
              self.source[self.position] == ',' ||
              self.source[self.position] == ')'
            ) {
            if (self.aggregate_resolve)(cell_reference(row, column))
              is Some(value) {
              arguments.push(value)
            }
          } else {
            self.position = saved
            arguments.push(self.expression(depth + 1))
          }
        }
        if arguments.length() > 10000 {
          raise InvalidWorkbook("formula argument bound exceeded")
        }
        if self.take(')') {
          break
        }
        if !self.take(',') {
          raise InvalidWorkbook("invalid formula argument separator")
        }
      }
      if token == "POWER" {
        if arguments.length() != 2 {
          raise InvalidWorkbook("POWER requires exactly two numeric arguments")
        }
        formula_power(arguments[0], arguments[1])
      } else if token == "COUNT" {
        arguments.length().to_double()
      } else if token == "AVERAGE" {
        if arguments.is_empty() {
          raise InvalidWorkbook("AVERAGE has no numeric values")
        }
        let mut sum = 0.0
        for argument in arguments {
          sum = formula_finite(sum + argument)
        }
        sum / arguments.length().to_double()
      } else if token == "ROUND" {
        if arguments.length() != 2 ||
          arguments[1].floor() != arguments[1] ||
          arguments[1] < -9.0 ||
          arguments[1] > 9.0 {
          raise InvalidWorkbook("ROUND requires a bounded integer precision")
        }
        let mut factor = 1.0
        let precision = arguments[1].to_int()
        for _ in 0..<precision.abs() {
          factor *= 10.0
        }
        if precision < 0 {
          factor = 1.0 / factor
        }
        let scaled = formula_finite(arguments[0] * factor)
        // Excel ROUND ties away from zero, including negative values.
        (if scaled < 0.0 {
          -(-scaled + 0.5).floor()
        } else {
          (scaled + 0.5).floor()
        }) /
        factor
      } else {
        let mut result = if token == "SUM" { 0.0 } else { arguments[0] }
        for argument in arguments {
          if token == "SUM" {
            result += argument
          } else if token == "MIN" {
            result = result.min(argument)
          } else {
            result = result.max(argument)
          }
        }
        result
      }
    } else if parse_cell_reference(token.replace_all(old="$", new=""))
      is Some((row, column)) {
      (self.resolve)(cell_reference(row, column))
    } else {
      @string.parse_double(token) catch {
        _ => raise InvalidWorkbook("unsupported numeric formula token")
      }
    }
  }
  let value = if self.take('%') { value / 100.0 } else { value }
  formula_finite(value)
}

///|
fn evaluate_formula(
  source : String,
  resolve : (String) -> Double raise XlsxError,
  aggregate_resolve : (String) -> Double? raise XlsxError,
) -> Double raise XlsxError {
  if source.length() == 0 || source.length() > 2048 {
    raise InvalidWorkbook("formula length bound exceeded")
  }
  let parser : FormulaParser = {
    source,
    position: 0,
    resolve,
    aggregate_resolve,
  }
  let _ = parser.take('=')
  let value = parser.expression(0)
  parser.skip()
  if parser.position != source.length() {
    raise InvalidWorkbook("unsupported formula syntax")
  }
  value
}

///|
fn recalculate_value(
  reference : String,
  cells : Map[String, @xml.Element],
  values : Map[String, Double],
  visiting : Map[String, Bool],
  budget : Ref[Int],
  depth : Int,
) -> Double raise XlsxError {
  budget.val -= 1
  if budget.val < 0 || depth > 64 {
    raise InvalidWorkbook("formula evaluation bound exceeded")
  }
  if values.get(reference) is Some(value) {
    return value
  }
  if visiting.get(reference) == Some(true) {
    raise InvalidWorkbook("circular formula reference")
  }
  guard cells.get(reference) is Some(cell) else { return 0.0 }
  visiting[reference] = true
  let value = if cell.first_child("f") is Some(formula) {
    if formula.attributes.length() != 0 {
      raise InvalidWorkbook(
        "shared, array and data-table formulas are unsupported",
      )
    }
    evaluate_formula(
      formula.text_content(),
      other => {
        recalculate_value(other, cells, values, visiting, budget, depth + 1)
      },
      other => {
        aggregate_recalculate_value(
          other,
          cells,
          values,
          visiting,
          budget,
          depth + 1,
        )
      },
    )
  } else {
    if cell.attribute("t") == Some("e") ||
      cell.attribute("t") == Some("b") ||
      cell.attribute("t") == Some("s") {
      raise InvalidWorkbook("formula references a non-numeric or error cell")
    }
    let text = if cell.attribute("t") == Some("inlineStr") {
      cell
      .first_child("is")
      .map(element => element.text_content())
      .unwrap_or("")
    } else {
      child_text(cell, "v").unwrap_or("")
    }
    if text.trim() == "" {
      0.0
    } else {
      @string.parse_double(text.trim()) catch {
        _ => raise InvalidWorkbook("formula references a non-numeric cell")
      }
    }
  }
  let value = formula_finite(value)
  visiting[reference] = false
  values[reference] = value
  value
}

///|
fn aggregate_recalculate_value(
  reference : String,
  cells : Map[String, @xml.Element],
  values : Map[String, Double],
  visiting : Map[String, Bool],
  budget : Ref[Int],
  depth : Int,
) -> Double? raise XlsxError {
  budget.val -= 1
  if budget.val < 0 || depth > 64 {
    raise InvalidWorkbook("formula evaluation bound exceeded")
  }
  guard cells.get(reference) is Some(cell) else { return None }
  if cell.first_child("f") is Some(_) {
    return Some(
      recalculate_value(reference, cells, values, visiting, budget, depth),
    )
  }
  if cell.attribute("t") == Some("e") {
    raise InvalidWorkbook("formula references an error cell")
  }
  if [Some("b"), Some("s"), Some("inlineStr"), Some("str")].contains(
      cell.attribute("t"),
    ) {
    return None
  }
  if child_text(cell, "v").unwrap_or("").trim().is_blank() {
    return None
  }
  Some(recalculate_value(reference, cells, values, visiting, budget, depth))
}

///|
fn write_formula_cache(
  root : @xml.Element,
  values : Map[String, Double],
) -> @xml.Element {
  if root.local_name() == "c" && root.first_child("f") is Some(_) {
    let reference = match
      parse_cell_reference(root.attribute("r").unwrap_or("")) {
      Some((row, column)) => cell_reference(row, column)
      None => ""
    }
    let children = root.children.filter(child => {
      match child {
        Element(element) => element.local_name() != "v"
        _ => true
      }
    })
    let prefix = root.name.strip_suffix("c").unwrap_or("").to_owned()
    children.push(
      Element({
        name: prefix + "v",
        attributes: [],
        children: [Text(values[reference].to_string())],
      }),
    )
    {
      name: root.name,
      attributes: root.attributes.filter(attribute => attribute.name != "t"),
      children,
    }
  } else {
    {
      name: root.name,
      attributes: root.attributes,
      children: root.children.map(child => {
        match child {
          Element(element) => Element(write_formula_cache(element, values))
          Text(_) => child
        }
      }),
    }
  }
}

///|
/// Recompute and replace every formula cache from source cells, never from
/// cached formula values. Supports same-sheet A1/$A$1 references, arithmetic,
/// percentages, SUM/MIN/MAX/AVERAGE/COUNT rectangular ranges and ROUND (precision -9..9).
/// Unsupported functions, external/cross-sheet references, shared/array
/// formulas, cycles, numeric errors and excessive work fail closed. This
/// deterministic IEEE-754 subset is for reviewed quote templates, not general
/// Excel compatibility or the authoritative integer-money commercial ledger.
pub fn recalculate(archive : @opc.Package) -> @opc.Package raise XlsxError {
  let workbook = parse_part(archive, "xl/workbook.xml")
  let relationships = workbook_relationships(archive)
  let mut result = archive
  let budget = Ref(200000)
  let mut total_cells = 0
  for sheet in workbook_sheets(workbook) {
    let part = worksheet_part_name(relationships, sheet)
    let root = parse_part(archive, part)
    let cells : Map[String, @xml.Element] = Map([])
    if root.first_child("sheetData") is Some(data) {
      for row in data.children_named("row") {
        for cell in row.children_named("c") {
          total_cells += 1
          if total_cells > 10000 {
            raise InvalidWorkbook("recalculation cell bound exceeded")
          }
          guard cell.attribute("r") is Some(source_reference) &&
            parse_cell_reference(source_reference) is Some((row, column)) else {
            raise InvalidWorkbook(
              "recalculation requires unique explicit cell references",
            )
          }
          // Readers and editors identify cells by parsed coordinates, so A01
          // and A1 must share a calculation key too. Keep the XML spelling.
          let reference = cell_reference(row, column)
          if cells.contains(reference) {
            raise InvalidWorkbook(
              "recalculation requires unique explicit cell references",
            )
          }
          if cell.attribute("t") == Some("e") && cell.first_child("f") is None {
            raise InvalidWorkbook("workbook contains an error cell")
          }
          cells[reference] = cell
        }
      }
    }
    let values : Map[String, Double] = Map([])
    let visiting : Map[String, Bool] = Map([])
    for reference, cell in cells {
      if cell.first_child("f") is Some(_) {
        ignore(recalculate_value(reference, cells, values, visiting, budget, 0))
      }
    }
    result = result.replace_text(
      part,
      @xml.serialize(write_formula_cache(root, values)),
    )
  }
  result
}
