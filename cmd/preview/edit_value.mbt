///|
fn formula_count(archive : @opc.Package) -> Int32 {
  let workbook = @xlsx.read(archive) catch {
    error => abort("MoonLeaf workbook reopen failed: \{Repr(error)}")
  }
  let mut count = 0
  for sheet in workbook.sheets {
    for cell in sheet.cells {
      if cell.value is Formula(..) {
        count += 1
      }
    }
  }
  count
}

///|
fn recalculate_file(args : Array[String]) -> Unit {
  if args.length() != 6 {
    abort("usage: moonleaf-preview recalculate SOURCE NAME OUTPUT")
  }
  if !args[4].to_lower().has_suffix(".xlsx") {
    abort("recalculation requires XLSX")
  }
  let archive = @opc.open(read_file(args[3])) catch {
    error => abort("MoonLeaf XLSX open failed: \{Repr(error)}")
  }
  let edited = @xlsx.recalculate(archive) catch {
    error => abort("MoonLeaf recalculation failed: \{Repr(error)}")
  }
  let count = formula_count(edited)
  let bytes = @opc.save(edited) catch {
    error => abort("MoonLeaf save failed: \{Repr(error)}")
  }
  write_file(args[5], bytes)
  println(
    (
      {
        "contract": "moonleaf.workbook-recalculate.v1",
        "recalculated_formulas": ToJson::to_json(count),
      } : Json).stringify(),
  )
}

///|
fn edit_value(args : Array[String]) -> Unit {
  if args.length() != 6 {
    abort("usage: moonleaf-preview edit-value SOURCE NAME OUTPUT")
  }
  let raw = read_stdin()
  if raw.length() > 65536 {
    abort("cell value request exceeds 65536 characters")
  }
  let request = @json.parse(raw) catch {
    _ => abort("invalid cell value request JSON")
  }
  guard request is Object(fields) &&
    fields.length() == 5 &&
    fields
    .keys()
    .all(key => ["sheet", "row", "column", "value_type", "value"].contains(key)) &&
    fields.get("sheet") is Some(String(sheet)) &&
    fields.get("row") is Some(Number(r, ..)) &&
    fields.get("column") is Some(Number(c, ..)) &&
    fields.get("value_type") is Some(String(value_type)) &&
    fields.get("value") is Some(String(value)) else {
    abort(
      "cell value request requires sheet, row, column, value_type and string value",
    )
  }
  if r < 1 ||
    r > 10000 ||
    c < 1 ||
    c > 256 ||
    r.to_int().to_double() != r ||
    c.to_int().to_double() != c ||
    !["text", "number", "formula"].contains(value_type) ||
    value.length() > 32768 {
    abort("invalid cell value coordinates, type or length")
  }
  let row = r.to_int()
  let column = c.to_int()
  let mut count = 0
  let receipt : Map[String, Json] = {
    "contract": Json::string("moonleaf.cell-value-edit.v1"),
    "sheet": Json::string(sheet),
    "row": ToJson::to_json(row),
    "column": ToJson::to_json(column),
    "value_type": Json::string(value_type),
  }
  if args[4].to_lower().has_suffix(".xlsx") {
    let archive = @opc.open(read_file(args[3])) catch {
      error => abort("MoonLeaf XLSX open failed: \{Repr(error)}")
    }
    let edited = @xlsx.set_cell_value(
      archive, sheet, row, column, value_type, value,
    ) catch {
      error => abort("MoonLeaf value edit failed: \{Repr(error)}")
    }
    count = formula_count(edited)
    let bytes = @opc.save(edited) catch {
      error => abort("MoonLeaf save failed: \{Repr(error)}")
    }
    if value_type == "formula" {
      receipt["formula"] = Json::string(
        value.trim().strip_prefix("=").unwrap_or(value.trim()).to_owned(),
      )
    }
    write_file(args[5], bytes)
  } else if args[4].to_lower().has_suffix(".csv") ||
    args[4].to_lower().has_suffix(".tsv") {
    if value_type == "formula" {
      abort("formula editing requires XLSX")
    }
    if sheet != "工作表1" {
      abort("unknown CSV sheet")
    }
    let original = @utf8.decode(Bytes::from_array(read_file(args[3]))) catch {
      _ => abort("invalid UTF-8")
    }
    let delimiter = if args[4].to_lower().has_suffix(".tsv") {
      '\t'
    } else {
      ','
    }
    let table = @csv.parse(original, delimiter~) catch {
      _ => abort("MoonLeaf CSV open failed")
    }
    let stored = if value_type == "number" {
      let number = @string.parse_double(value.trim()) catch {
        _ => abort("invalid numeric value")
      }
      if number.is_inf() || number.is_nan() {
        abort("numeric value must be finite")
      }
      number.to_string()
    } else {
      safe_csv_text(value)
    }
    let edited = table.set_cell_text(row, column, stored) catch {
      _ => abort("MoonLeaf CSV cell edit failed")
    }
    write_file(args[5], verified_delimited_bytes(edited, original))
  } else {
    abort("unsupported spreadsheet format")
  }
  receipt["recalculated_formulas"] = ToJson::to_json(count)
  println(Json::object(receipt).stringify())
}
