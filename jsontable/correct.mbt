///|
pub(all) suberror CorrectionError {
  InvalidCorrection(String)
  CorrectionConflict(edit~ : Int32, row~ : Int32, column~ : String)
} derive(Debug, Eq)

///|
priv struct CellCorrection {
  key : Array[String]
  column : String
  before : @scene.CellValue
  after : @scene.CellValue
}

///|
/// An explicitly parsed, typed batch. Keys and edits are not mutable by callers.
pub struct CorrectionRecipe {
  priv key_columns : Array[String]
  priv edits : Array[CellCorrection]
}

///|
pub(all) struct CorrectionResult {
  table : Table
  report : Table
} derive(Debug, Eq)

///|
fn correction_object(
  value : Json,
  allowed : Array[String],
) -> Map[String, Json] raise CorrectionError {
  guard value is Object(object) else {
    raise InvalidCorrection("Expected an object")
  }
  for name, _ in object {
    if !allowed.contains(name) {
      raise InvalidCorrection("Unknown recipe field: " + name)
    }
  }
  object
}

///|
fn correction_strings(value : Json?) -> Array[String] raise CorrectionError {
  guard value is Some(Array(values)) &&
    !values.is_empty() &&
    values.length() <= 32 else {
    raise InvalidCorrection("Expected 1–32 nonempty text key components")
  }
  let strings : Array[String] = []
  for value in values {
    guard value is String(text) && text != "" && text.length() <= 4096 else {
      raise InvalidCorrection(
        "Key components must be nonempty strings up to 4096 units",
      )
    }
    strings.push(text)
  }
  strings
}

///|
fn correction_scalar(value : @scene.CellValue) -> Unit raise CorrectionError {
  match value {
    Empty | Text(_) | Boolean(_) => ()
    Number(text) => {
      let json = @json.parse(text) catch {
        _ => raise InvalidCorrection("Invalid numeric cell")
      }
      guard json is Number(number, ..) &&
        !number.is_inf() &&
        !number.is_nan() &&
        text == text.trim().to_owned() else {
        raise InvalidCorrection(
          "Expected a finite JSON number without surrounding whitespace",
        )
      }
    }
    _ =>
      raise InvalidCorrection(
        "Only text, finite number, boolean and empty cells are supported",
      )
  }
}

///|
fn correction_cell(value : Json?) -> @scene.CellValue raise CorrectionError {
  guard value is Some(value) else {
    raise InvalidCorrection("Missing before or after cell")
  }
  let object = correction_object(value, ["type", "value"])
  let cell : @scene.CellValue = match object.get("type") {
    Some(String("empty")) => {
      if object.contains("value") {
        raise InvalidCorrection("Empty cells must omit value")
      }
      Empty
    }
    Some(String("text")) =>
      match object.get("value") {
        Some(String(text)) => Text(text)
        _ => raise InvalidCorrection("Text cells require a string value")
      }
    Some(String("number")) =>
      match object.get("value") {
        Some(String(text)) => Number(text)
        _ =>
          raise InvalidCorrection(
            "Number cells require an exact JSON-number string",
          )
      }
    Some(String("boolean")) =>
      match object.get("value") {
        Some(True) => Boolean(true)
        Some(False) => Boolean(false)
        _ => raise InvalidCorrection("Boolean cells require true or false")
      }
    _ =>
      raise InvalidCorrection(
        "Expected cell type text, number, boolean or empty",
      )
  }
  correction_scalar(cell)
  cell
}

///|
/// Parse a strict typed correction recipe. Numeric strings are compared exactly;
/// text, number, boolean and empty are distinct. No coercion is performed.
pub fn parse_correction_recipe(
  text : String,
) -> CorrectionRecipe raise CorrectionError {
  if text.length() > 1_048_576 {
    raise InvalidCorrection("Recipe exceeds 1048576 UTF-16 units")
  }
  let value = @json.parse(text) catch {
    _ => raise InvalidCorrection("Invalid recipe JSON")
  }
  let object = correction_object(value, ["key_columns", "edits"])
  let key_columns = correction_strings(object.get("key_columns"))
  let names : Map[String, Bool] = Map([])
  for name in key_columns {
    if names.contains(name) {
      raise InvalidCorrection("Duplicate key column: " + name)
    }
    names[name] = true
  }
  guard object.get("edits") is Some(Array(items)) &&
    !items.is_empty() &&
    items.length() <= 1000 else {
    raise InvalidCorrection("Expected 1–1000 cell edits")
  }
  let edits : Array[CellCorrection] = []
  for item in items {
    let item = correction_object(item, ["key", "column", "before", "after"])
    let key = correction_strings(item.get("key"))
    if key.length() != key_columns.length() {
      raise InvalidCorrection("Key arity differs from key_columns")
    }
    guard item.get("column") is Some(String(column)) && column != "" else {
      raise InvalidCorrection("Missing nonempty edit column")
    }
    if names.contains(column) {
      raise InvalidCorrection("Key columns cannot be edited")
    }
    edits.push({
      key,
      column,
      before: correction_cell(item.get("before")),
      after: correction_cell(item.get("after")),
    })
  }
  { key_columns, edits, }
}

///|
fn correction_type(cell : @scene.CellValue) -> String {
  match cell {
    Empty => "empty"
    Text(_) => "text"
    Number(_) => "number"
    Boolean(_) => "boolean"
    _ => "unsupported"
  }
}

///|
/// Validate all keys and expected old values, then return a fresh edited table
/// and a recipe-ordered before/after report. The source never changes, including
/// on late failure. Keys must be globally unique exact nonempty text tuples.
pub fn Table::correct(
  self : Table,
  recipe : CorrectionRecipe,
) -> CorrectionResult raise CorrectionError {
  if self.columns.is_empty() ||
    self.columns.length() > 128 ||
    self.rows.length() > 10000 ||
    (self.rows.length() + 1) * self.columns.length() > 100000 {
    raise InvalidCorrection(
      "Expected 1–128 columns, at most 10000 rows and 100000 cells including header",
    )
  }
  validate_lookup_table(self) catch {
    _ =>
      raise InvalidCorrection(
        "Expected unique nonempty headers and rectangular rows",
      )
  }
  let key_indexes : Array[Int32] = []
  for name in recipe.key_columns {
    key_indexes.push(
      lookup_column(self, name) catch {
        _ => raise InvalidCorrection("Unknown key column: " + name)
      },
    )
  }
  let index : Map[String, Int32] = Map([])
  let mut units = 0
  for name in self.columns {
    units += name.length()
  }
  if units > 4_000_000 {
    raise InvalidCorrection("Table exceeds 4000000 text units")
  }
  for r, row in self.rows {
    for cell in row {
      correction_scalar(cell)
      match cell {
        Text(text) | Number(text) => units += text.length()
        _ => ()
      }
      if units > 4_000_000 {
        raise InvalidCorrection("Table exceeds 4000000 text units")
      }
    }
    let key : Array[Json] = []
    for c in key_indexes {
      guard row[c] is Text(text) && text != "" && text.length() <= 4096 else {
        raise InvalidCorrection(
          "Row \{r + 1} has a missing, empty, nontext or oversized key",
        )
      }
      key.push(Json::string(text))
    }
    let identity = Json::array(key).stringify()
    if index.contains(identity) {
      raise InvalidCorrection("Duplicate source key at row \{r + 1}")
    }
    index[identity] = r
  }
  let targets : Map[String, Bool] = Map([])
  let coordinates : Array[(Int32, Int32)] = []
  let reports : Array[Array[@scene.CellValue]] = []
  for i, edit in recipe.edits {
    let identity = Json::array(edit.key.map(Json::string)).stringify()
    guard index.get(identity) is Some(r) else {
      raise InvalidCorrection("Edit \{i + 1} key was not found")
    }
    let c = lookup_column(self, edit.column) catch {
      _ => raise InvalidCorrection("Unknown edit column: " + edit.column)
    }
    let target = "\{r}:\{c}"
    if targets.contains(target) {
      raise InvalidCorrection("Repeated target cell at edit \{i + 1}")
    }
    targets[target] = true
    if self.rows[r][c] != edit.before {
      raise CorrectionConflict(edit=i + 1, row=r + 1, column=edit.column)
    }
    coordinates.push((r, c))
    reports.push([
      Number((i + 1).to_string()),
      Number((r + 1).to_string()),
      Text(identity),
      Text(edit.column),
      Text(correction_type(edit.before)),
      edit.before,
      Text(correction_type(edit.after)),
      edit.after,
      Text(if edit.before == edit.after { "unchanged" } else { "changed" }),
    ])
  }
  let rows = self.rows.map(row => row.copy())
  for i, coordinate in coordinates {
    let (r, c) = coordinate
    rows[r][c] = recipe.edits[i].after
  }
  {
    table: { columns: self.columns.copy(), rows, },
    report: {
      columns: [
        "edit", "input_row", "key", "column", "before_type", "before", "after_type",
        "after", "status",
      ],
      rows: reports,
    },
  }
}

///|
pub extend CorrectionError with @debug.Debug::{to_repr}

///|
pub extend CorrectionError with Eq::{not_equal, equal}

///|
pub extend CorrectionResult with @debug.Debug::{to_repr}

///|
pub extend CorrectionResult with Eq::{not_equal, equal}
