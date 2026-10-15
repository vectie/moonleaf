///|
pub(all) suberror QueryError {
  InvalidQuery(String)
} derive(Debug, Eq)

///|
priv struct QueryFilter {
  column : String
  mode : String
  operation : String
  value : @scene.CellValue
}

///|
priv struct QuerySort {
  column : String
  mode : String
  descending : Bool
  blanks_first : Bool
}

///|
/// Validated version-1 recipe, reusable against tables with matching columns.
pub struct QueryRecipe {
  priv filters : Array[QueryFilter]
  priv sort : Array[QuerySort]
  priv select : Array[String]
  priv limit : Int
}

///|
pub(all) struct QueryResult {
  table : Table
  source_rows : Array[Int]
  matched_rows : Int
} derive(Debug, Eq)

///|
fn query_fields(
  value : Json,
  names : Array[String],
) -> Map[String, Json] raise QueryError {
  guard value is Object(fields) &&
    fields.length() == names.length() &&
    names.all(name => fields.contains(name)) else {
    raise InvalidQuery("Expected exactly these fields: " + names.join(", "))
  }
  fields
}

///|
fn query_string(
  fields : Map[String, Json],
  name : String,
) -> String raise QueryError {
  guard fields.get(name) is Some(String(value)) else {
    raise InvalidQuery("Expected string: " + name)
  }
  value
}

///|
fn query_mode(mode : String) -> Unit raise QueryError {
  if !["text", "number", "boolean"].contains(mode) {
    raise InvalidQuery("Mode must be text, number or boolean")
  }
}

///|
/// Read a strict bounded JSON recipe. Unknown or missing fields fail closed.
pub fn parse_query_recipe(text : String) -> QueryRecipe raise QueryError {
  if text.length() > 65536 {
    raise InvalidQuery("Recipe exceeds 65536 code units")
  }
  let json = @json.parse(text) catch {
    _ => raise InvalidQuery("Invalid recipe JSON")
  }
  let fields = query_fields(json, [
    "version", "filters", "sort", "select", "limit",
  ])
  guard fields.get("version") == Some(Json::number(1)) &&
    fields.get("filters") is Some(Array(filters)) &&
    fields.get("sort") is Some(Array(sort)) &&
    fields.get("select") is Some(Array(select)) &&
    fields.get("limit") is Some(Number(limit, ..)) &&
    limit >= 0 &&
    limit <= 10000 &&
    limit == limit.to_int().to_double() else {
    raise InvalidQuery(
      "Expected version 1, array filters/sort/select, integer limit 0–10000",
    )
  }
  if filters.length() > 32 ||
    sort.length() > 8 ||
    select.is_empty() ||
    select.length() > 256 {
    raise InvalidQuery(
      "Expected at most 32 filters, 8 sort keys and 1–256 selected columns",
    )
  }
  let parsed_filters : Array[QueryFilter] = []
  for filter in filters {
    let f = query_fields(filter, ["column", "mode", "op", "value"])
    let column = query_string(f, "column")
    let mode = query_string(f, "mode")
    query_mode(mode)
    let operation = query_string(f, "op")
    if ![
        "eq", "ne", "lt", "le", "gt", "ge", "contains", "is_blank", "not_blank",
      ].contains(operation) {
      raise InvalidQuery("Unknown filter operation: " + operation)
    }
    if operation == "contains" && mode != "text" {
      raise InvalidQuery("contains requires text mode")
    }
    let value = if operation == "is_blank" || operation == "not_blank" {
      if !(f["value"] is Null) {
        raise InvalidQuery("Blank tests require null value")
      }
      @scene.CellValue::Empty
    } else {
      let value : @scene.CellValue = match f["value"] {
        String(v) => Text(v)
        Number(_) => Number(f["value"].stringify())
        True => Boolean(true)
        False => Boolean(false)
        _ =>
          raise InvalidQuery(
            "Comparison value must be scalar text, number or boolean",
          )
      }
      ignore(query_value(value, mode, "filter value"))
      if query_blank(value) {
        raise InvalidQuery("Use is_blank to match blanks")
      }
      value
    }
    parsed_filters.push({ column, mode, operation, value, })
  }
  let parsed_sort : Array[QuerySort] = []
  let sort_names : Array[String] = []
  for key in sort {
    let f = query_fields(key, ["column", "mode", "direction", "blanks"])
    let column = query_string(f, "column")
    let mode = query_string(f, "mode")
    query_mode(mode)
    let direction = query_string(f, "direction")
    let blanks = query_string(f, "blanks")
    if sort_names.contains(column) ||
      !["asc", "desc"].contains(direction) ||
      !["first", "last"].contains(blanks) {
      raise InvalidQuery(
        "Sort keys must be unique with asc/desc and first/last blanks",
      )
    }
    sort_names.push(column)
    parsed_sort.push({
      column,
      mode,
      descending: direction == "desc",
      blanks_first: blanks == "first",
    })
  }
  let names : Array[String] = []
  for item in select {
    guard item is String(name) && name != "" && !names.contains(name) else {
      raise InvalidQuery("Selected columns must be unique nonempty strings")
    }
    names.push(name)
  }
  {
    filters: parsed_filters,
    sort: parsed_sort,
    select: names,
    limit: limit.to_int(),
  }
}

///|
fn query_blank(value : @scene.CellValue) -> Bool {
  value == Empty || value == Text("")
}

///|
priv enum QueryValue {
  Blank
  TextValue(String)
  NumberValue(Double)
  BoolValue(Bool)
}

///|
fn query_value(
  value : @scene.CellValue,
  mode : String,
  context : String,
) -> QueryValue raise QueryError {
  if query_blank(value) {
    return Blank
  }
  match (mode, value) {
    ("text", Text(text)) => TextValue(text)
    ("boolean", Boolean(flag)) => BoolValue(flag)
    ("number", Text(text) | Number(text)) => {
      let json = @json.parse(text) catch {
        _ => raise InvalidQuery("Invalid number at " + context)
      }
      guard json is Number(number, ..) && !number.is_inf() && !number.is_nan() else {
        raise InvalidQuery("Expected finite JSON number at " + context)
      }
      NumberValue(number)
    }
    _ =>
      raise InvalidQuery("Value does not match " + mode + " mode at " + context)
  }
}

///|
fn query_compare(a : QueryValue, b : QueryValue) -> Int {
  match (a, b) {
    (TextValue(a), TextValue(b)) => {
      // String::compare uses shortlex; recipes promise UTF-16 lexical order.
      for i in 0..<Int::min(a.length(), b.length()) {
        let order = a.code_unit_at(i).compare(b.code_unit_at(i))
        if order != 0 {
          return order
        }
      }
      a.length().compare(b.length())
    }
    (NumberValue(a), NumberValue(b)) =>
      if a < b {
        -1
      } else if a > b {
        1
      } else {
        0
      }
    (BoolValue(a), BoolValue(b)) => if a == b { 0 } else if a { 1 } else { -1 }
    _ => 0
  }
}

///|
fn query_matches(
  value : QueryValue,
  filter : QueryFilter,
  wanted : QueryValue,
) -> Bool {
  match filter.operation {
    "is_blank" => value is Blank
    "not_blank" => !(value is Blank)
    _ if value is Blank => false
    "contains" =>
      match (value, wanted) {
        (TextValue(a), TextValue(b)) => a.contains(b)
        _ => false
      }
    op => {
      let order = query_compare(value, wanted)
      match op {
        "eq" => order == 0
        "ne" => order != 0
        "lt" => order < 0
        "le" => order <= 0
        "gt" => order > 0
        _ => order >= 0
      }
    }
  }
}

///|
fn query_column(table : Table, name : String) -> Int raise QueryError {
  lookup_column(table, name) catch {
    _ => raise InvalidQuery("Unknown column: " + name)
  }
}

///|
/// Validate all inputs, AND filters, sort lexicographically with stable ties,
/// take the explicit limit, then project a fresh table. Row identities are
/// one-based input data rows. No source cells or recipe arrays are mutated.
pub fn Table::query(
  self : Table,
  recipe : QueryRecipe,
) -> QueryResult raise QueryError {
  if self.columns.is_empty() ||
    self.columns.length() > 256 ||
    self.rows.length() > 10000 ||
    (self.rows.length() + 1) * self.columns.length() > 100000 {
    raise InvalidQuery(
      "Input needs 1–256 columns, at most 10000 rows and 100000 cells including header",
    )
  }
  validate_lookup_table(self) catch {
    _ =>
      raise InvalidQuery(
        "Expected unique nonempty headers and rectangular rows",
      )
  }
  let projected = recipe.select.map(name => query_column(self, name))
  let filter_columns = recipe.filters.map(f => query_column(self, f.column))
  let sort_columns = recipe.sort.map(s => query_column(self, s.column))
  let wanted = recipe.filters.map(f => {
    query_value(f.value, f.mode, "filter value")
  })
  let indices : Array[Int] = []
  let sort_values : Array[Array[QueryValue]] = []
  for i, row in self.rows {
    for value in row {
      match value {
        Empty | Text(_) | Number(_) | Boolean(_) => ()
        _ =>
          raise InvalidQuery("Unsupported formula/error cell at row \{i + 1}")
      }
    }
    let keys : Array[QueryValue] = []
    for k, sort in recipe.sort {
      keys.push(
        query_value(
          row[sort_columns[k]],
          sort.mode,
          "row \{i + 1}, column " + sort.column,
        ),
      )
    }
    sort_values.push(keys)
    let mut matches = true
    for k, filter in recipe.filters {
      let value = if filter.operation == "is_blank" ||
        filter.operation == "not_blank" {
        if query_blank(row[filter_columns[k]]) {
          Blank
        } else {
          TextValue("present")
        }
      } else {
        query_value(
          row[filter_columns[k]],
          filter.mode,
          "row \{i + 1}, column " + filter.column,
        )
      }
      if !query_matches(value, filter, wanted[k]) {
        matches = false
      }
    }
    if matches {
      indices.push(i)
    }
  }
  indices.sort_by((a, b) => {
    for k, key in recipe.sort {
      let av = sort_values[a][k]
      let bv = sort_values[b][k]
      let order = match (av, bv) {
        (Blank, Blank) => 0
        (Blank, _) => if key.blanks_first { -1 } else { 1 }
        (_, Blank) => if key.blanks_first { 1 } else { -1 }
        _ => {
          let order = query_compare(av, bv)
          if key.descending {
            -order
          } else {
            order
          }
        }
      }
      if order != 0 {
        return order
      }
    }
    a.compare(b)
  })
  let count = Int::min(indices.length(), recipe.limit)
  let selected = indices[:count].to_owned()
  {
    table: {
      columns: recipe.select.copy(),
      rows: selected.map(i => projected.map(c => self.rows[i][c])),
    },
    source_rows: selected.map(i => i + 1),
    matched_rows: indices.length(),
  }
}

///|
pub extend QueryError with @debug.Debug::{to_repr}

///|
pub extend QueryError with Eq::{not_equal, equal}

///|
pub extend QueryResult with @debug.Debug::{to_repr}

///|
pub extend QueryResult with Eq::{not_equal, equal}
