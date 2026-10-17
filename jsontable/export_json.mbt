///|
/// Export a reusable JSON array of objects. Empty cells become null by default;
/// omit_empty=true omits those object keys, preserving missing fields when the
/// JSON is parsed again (all-missing columns and empty-table schema still need
/// the original column list). Text,
/// booleans and finite numbers retain their types. Formula/error cells are not
/// evaluated or silently flattened. Parsing this JSON again follows parse's
/// existing null-to-text projection, so this is not a lossless Table codec.
pub fn Table::export_json(
  self : Table,
  omit_empty~ : Bool = false,
) -> String raise TableError {
  validate_lookup_table(self) catch {
    _ => raise Export("Expected unique nonempty columns and rectangular rows")
  }
  let objects : Array[Json] = []
  for i, row in self.rows {
    let object : Map[String, Json] = Map([])
    for j, value in row {
      if omit_empty && value == Empty {
        continue
      }
      object[self.columns[j]] = match value {
        Empty => Json::null()
        Text(text) => Json::string(text)
        Boolean(flag) => Json::boolean(flag)
        Number(text) => {
          let number = @json.parse(text) catch {
            _ =>
              raise Export(
                "Invalid number at data row \{i + 1}, column \{j + 1}",
              )
          }
          guard number is Number(value, ..) &&
            !value.is_inf() &&
            !value.is_nan() else {
            raise Export("Invalid number at data row \{i + 1}, column \{j + 1}")
          }
          number
        }
        _ =>
          raise Export("Unsupported cell at data row \{i + 1}, column \{j + 1}")
      }
    }
    objects.push(Json::object(object))
  }
  Json::array(objects).stringify()
}
