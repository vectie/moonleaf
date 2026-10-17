///|
pub(all) enum StackMode {
  StrictHeaders
  UnionHeaders
} derive(Debug, Eq)

///|
pub(all) suberror StackError {
  InvalidStack(String)
} derive(Debug, Eq)

///|
/// Append scalar datasets by exact header names, preserving source and row order.
/// Strict mode requires the same header set, allowing reordered input columns.
/// Union mode appends newly encountered headers and fills absent cells with Empty.
/// Provenance is included as two trailing columns; row numbers exclude headers.
pub fn stack(
  tables : Array[Table],
  sources~ : Array[String],
  mode~ : StackMode,
  source_column~ : String = "_source",
  row_column~ : String = "_source_row",
) -> Table raise StackError {
  if tables.is_empty() ||
    tables.length() > 64 ||
    tables.length() != sources.length() {
    raise InvalidStack("Expected 1 to 64 tables with matching source labels")
  }
  if source_column == "" || row_column == "" || source_column == row_column {
    raise InvalidStack("Provenance column names must be nonempty and distinct")
  }
  let labels : Array[String] = []
  let columns : Array[String] = []
  let mut total = 0
  for i, table in tables {
    if sources[i] == "" || labels.contains(sources[i]) {
      raise InvalidStack("Source labels must be nonempty and unique")
    }
    labels.push(sources[i])
    validate_lookup_table(table) catch {
      _ =>
        raise InvalidStack(
          "Expected unique nonempty headers and rectangular rows",
        )
    }
    if table.columns.is_empty() {
      raise InvalidStack("Each source needs at least one header")
    }
    for name in table.columns {
      if name == source_column || name == row_column {
        raise InvalidStack("Source header collides with provenance: " + name)
      }
      if !columns.contains(name) {
        if i > 0 && mode == StrictHeaders {
          raise InvalidStack("Strict header mismatch in source: " + sources[i])
        }
        columns.push(name)
      }
    }
    if mode == StrictHeaders && table.columns.length() != columns.length() {
      raise InvalidStack("Strict header mismatch in source: " + sources[i])
    }
    total += table.rows.length()
    if columns.length() + 2 > 256 ||
      total > 10_000 ||
      (total + 1) * (columns.length() + 2) > 100_000 {
      raise InvalidStack(
        "Result exceeds 256 columns, 10000 rows or 100000 cells including header",
      )
    }
  }
  let rows : Array[Array[@scene.CellValue]] = []
  for i, table in tables {
    let positions = columns.map(name => {
      let mut position : Int32? = None
      for j, header in table.columns {
        if name == header {
          position = Some(j)
        }
      }
      position
    })
    for r, row in table.rows {
      let output = positions.map(position => {
        match position {
          None => @scene.CellValue::Empty
          Some(j) => row[j]
        }
      })
      for value in output {
        match value {
          Empty | Text(_) | Number(_) | Boolean(_) => ()
          _ =>
            raise InvalidStack(
              "Formula or error cell in source \{sources[i]}, data row \{r + 1}",
            )
        }
      }
      output.push(Text(sources[i]))
      output.push(Number((r + 1).to_string()))
      rows.push(output)
    }
  }
  columns.push(source_column)
  columns.push(row_column)
  { columns, rows, }
}

///|
pub extend StackMode with @debug.Debug::{to_repr}

///|
pub extend StackMode with Eq::{not_equal, equal}

///|
pub extend StackError with @debug.Debug::{to_repr}

///|
pub extend StackError with Eq::{not_equal, equal}
