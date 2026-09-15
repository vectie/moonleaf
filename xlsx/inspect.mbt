///|
/// Structured warning produced while inspecting display metadata.
pub(all) enum InspectWarning {
  MissingStylesPart
  StyleIdOutOfRange(Int)
  UnsupportedNumberFormat(Int, String)
  AmbiguousNumberFormat(Int, String)
} derive(Debug, Eq)

///|
/// Coarse display intent inferred from an XLSX number format.
pub(all) enum DisplayKind {
  General
  Number
  Date
  Time
  DateTime
  Unsupported
} derive(Debug, Eq)

///| Deterministic conversion of an Excel numeric serial.

///| `serial_60` marks the fictitious 1900-02-29 and therefore has no

///|
/// Gregorian year/month/day.
pub(all) struct DateTimeMetadata {
  date1904 : Bool
  serial : Double
  serial_60 : Bool
  year : Int?
  month : Int?
  day : Int?
  hour : Int
  minute : Int
  second : Int
} derive(Debug, Eq)

///|
/// Additive per-cell view retaining the XML value and cached formula value.
pub(all) struct InspectedCell {
  sheet_name : String
  row : Int
  column : Int
  raw_value : String?
  /// Resolved textual content for shared-string and inline-string cells.
  /// `raw_value` remains the original `<v>` text (including shared-string indexes).
  resolved_text : String?
  formula : String?
  cached_value : String?
  style_id : Int?
  number_format_id : Int?
  number_format : String?
  display_kind : DisplayKind
  date_time : DateTimeMetadata?
  warnings : Array[InspectWarning]
} derive(Debug, Eq)

///|
/// Exact workbook relationship types accepted for display metadata. Keeping
/// these private and exact prevents suffix-spoofed relationship types from
/// being interpreted as local workbook parts.
let styles_relationship_types : Array[String] = [
  "http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles", "http://purl.oclc.org/ooxml/officeDocument/relationships/styles",
]

///|
let shared_strings_relationship_types : Array[String] = [
  "http://schemas.openxmlformats.org/officeDocument/2006/relationships/sharedStrings",
  "http://purl.oclc.org/ooxml/officeDocument/relationships/sharedStrings",
]

///|
fn builtin_format(id : Int) -> String? {
  match id {
    0 => Some("General")
    1 => Some("0")
    2 => Some("0.00")
    3 => Some("#,##0")
    4 => Some("#,##0.00")
    5 => Some("$#,##0_);($#,##0)")
    6 => Some("$#,##0_);[Red]($#,##0)")
    7 => Some("$#,##0.00_);($#,##0.00)")
    8 => Some("$#,##0.00_);[Red]($#,##0.00)")
    9 => Some("0%")
    10 => Some("0.00%")
    11 => Some("0.00E+00")
    12 => Some("# ?/?")
    13 => Some("# ??/??")
    14 => Some("m/d/yy")
    15 => Some("d-mmm-yy")
    16 => Some("d-mmm")
    17 => Some("mmm-yy")
    18 => Some("h:mm AM/PM")
    19 => Some("h:mm:ss AM/PM")
    20 => Some("h:mm")
    21 => Some("h:mm:ss")
    22 => Some("m/d/yy h:mm")
    37 => Some("#,##0_);(#,##0)")
    38 => Some("#,##0_);[Red](#,##0)")
    39 => Some("#,##0.00_);(#,##0.00)")
    40 => Some("#,##0.00_);[Red](#,##0.00)")
    41 => Some("_(* #,##0_);_(* (#,##0);_(* \"-\"_);_(@_)")
    42 => Some("_($* #,##0_);_($* (#,##0);_($* \"-\"_);_(@_)")
    43 => Some("_(* #,##0.00_);_(* (#,##0.00);_(* \"-\"??_);_(@_)")
    44 => Some("_($* #,##0.00_);_($* (#,##0.00);_($* \"-\"??_);_(@_)")
    45 => Some("mm:ss")
    46 => Some("[h]:mm:ss")
    47 => Some("mmss.0")
    48 => Some("##0.0E+0")
    49 => Some("@")
    _ => None
  }
}

///|
fn custom_format_kind(code : String) -> (DisplayKind, Bool, Bool) {
  custom_format_kind_v2(code)
}

///|
fn format_kind(id : Int, code : String) -> (DisplayKind, Bool, Bool) {
  if id == 0 {
    (General, false, false)
  } else if (id >= 1 && id <= 13) ||
    (id >= 37 && id <= 44) ||
    id == 48 ||
    id == 49 {
    (Number, false, false)
  } else if id >= 14 && id <= 17 {
    (Date, false, false)
  } else if (id >= 18 && id <= 21) || id == 45 || id == 46 || id == 47 {
    (Time, false, false)
  } else if id == 22 {
    (DateTime, false, false)
  } else if builtin_format(id) is Some(_) {
    (Number, false, false)
  } else {
    custom_format_kind(code)
  }
}

///|
fn civil_from_days(days : Int) -> (Int, Int, Int) {
  let z = days + 719468
  let era = if z >= 0 { z / 146097 } else { (z - 146096) / 146097 }
  let doe = z - era * 146097
  let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
  let y0 = yoe + era * 400
  let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
  let mp = (5 * doy + 2) / 153
  let d = doy - (153 * mp + 2) / 5 + 1
  let m = mp + (if mp < 10 { 3 } else { -9 })
  (y0 + (if m <= 2 { 1 } else { 0 }), m, d)
}

///|
fn serial_metadata(serial : Double, date1904 : Bool) -> DateTimeMetadata? {
  // Bound the serial before converting Double to Int. This also rejects
  // positive infinity without a separate infinity check.
  let max_day = if date1904 { 2957003 } else { 2958465 }
  if serial.is_nan() || serial < 0.0 || serial >= max_day.to_double() + 1.0 {
    return None
  }
  let floored = serial.floor()
  let mut whole = floored.to_int()
  let fraction = serial - floored
  let mut seconds = (fraction * 86400.0).round().to_int()
  if seconds == 86400 {
    whole += 1
    seconds = 0
  }
  if whole > max_day {
    return None
  }
  let hour = seconds / 3600
  let minute = seconds % 3600 / 60
  let second = seconds % 60
  if !date1904 && whole == 60 {
    return Some({
      date1904,
      serial,
      serial_60: true,
      year: None,
      month: None,
      day: None,
      hour,
      minute,
      second,
    })
  }
  let adjustment = if whole < 60 { 1 } else { 0 }
  let unix_days = if date1904 {
    whole - 24107
  } else {
    whole - 25569 + adjustment
  }
  let (year, month, day) = civil_from_days(unix_days)
  Some({
    date1904,
    serial,
    serial_60: false,
    year: Some(year),
    month: Some(month),
    day: Some(day),
    hour,
    minute,
    second,
  })
}

///|
fn resolved_metadata_part(
  xlsx_package : @opc.Package,
  relationships : Array[@opc.Relationship],
  allowed_types : Array[String],
) -> @xml.Element? raise XlsxError {
  // Metadata relationships are singletons. Reject ambiguity before selecting
  // a target so an attacker cannot hide a later decoy behind a valid entry.
  let exact_internal_count = Ref(0)
  for relationship in relationships {
    if !relationship.external &&
      allowed_types.contains(relationship.relationship_type) {
      exact_internal_count.val = exact_internal_count.val + 1
    }
  }
  if exact_internal_count.val > 1 {
    raise PackageFailure(
      part="xl/_rels/workbook.xml.rels",
      message="duplicate internal exact-type metadata relationships",
    )
  }
  for relationship in relationships {
    if allowed_types.contains(relationship.relationship_type) &&
      !relationship.external {
      // Exact internal metadata relationships are authoritative. In
      // particular, an invalid target must fail closed through the existing
      // OPC-to-XlsxError mapping rather than being treated as a missing part.
      let target = @opc.resolve_target("xl/workbook.xml", relationship.target) catch {
        @opc.PackageError::InvalidPackage(message) =>
          raise XlsxError::PackageFailure(
            part="xl/_rels/workbook.xml.rels",
            message~,
          )
        @opc.PackageError::MissingPart(part) =>
          raise XlsxError::PackageFailure(part~, message="missing package part")
        @opc.PackageError::InvalidTextPart(part) =>
          raise XlsxError::PackageFailure(
            part~,
            message="package part is not valid UTF-8",
          )
      }
      if !xlsx_package.has_part(target) {
        raise XlsxError::PackageFailure(
          part=target,
          message="missing package part",
        )
      }
      return Some(parse_part(xlsx_package, target))
    }
  }
  None
}

///|
/// Inspect workbook cells without changing `read` or `scene.Cell`.
pub fn inspect(
  xlsx_package : @opc.Package,
) -> Array[InspectedCell] raise XlsxError {
  let relationships = workbook_relationships(xlsx_package)
  let strings = shared_strings(
    resolved_metadata_part(
      xlsx_package, relationships, shared_strings_relationship_types,
    ),
  )
  let workbook = parse_part(xlsx_package, "xl/workbook.xml")
  let date1904 = match workbook.first_child("workbookPr") {
    Some(p) =>
      p.attribute("date1904") == Some("1") ||
      p.attribute("date1904") == Some("true")
    None => false
  }
  let custom : Map[Int, String] = Map([])
  let xfs : Array[Int] = []
  let styles_part = resolved_metadata_part(
    xlsx_package, relationships, styles_relationship_types,
  )
  let styles_missing = styles_part is None
  match styles_part {
    Some(styles) => {
      match styles.first_child("numFmts") {
        Some(formats) =>
          for f in formats.children_named("numFmt") {
            match
              (
                integer_attribute(f, "numFmtId", 65535),
                f.attribute("formatCode"),
              ) {
              (Some(id), Some(code)) => custom[id] = code
              _ => ()
            }
          }
        None => ()
      }
      match styles.first_child("cellXfs") {
        Some(cell_xfs) =>
          for xf in cell_xfs.children_named("xf") {
            xfs.push(integer_attribute(xf, "numFmtId", 65535).unwrap_or(0))
          }
        None => ()
      }
    }
    None => ()
  }
  let relationships = workbook_relationships(xlsx_package)
  let result = []
  for sheet in workbook_sheets(workbook) {
    let root = parse_part(
      xlsx_package,
      worksheet_part_name(relationships, sheet),
    )
    match root.first_child("sheetData") {
      Some(data) => {
        let fallback_row = Ref(0)
        for row_element in data.children_named("row") {
          fallback_row.val = fallback_row.val + 1
          let row = integer_attribute(row_element, "r", max_row).unwrap_or(
            fallback_row.val,
          )
          fallback_row.val = row
          let fallback_column = Ref(0)
          for cell in row_element.children_named("c") {
            fallback_column.val = fallback_column.val + 1
            let (cell_row, column) = match cell.attribute("r") {
              Some(reference) =>
                match parse_cell_reference(reference) {
                  Some(position) => position
                  None => raise InvalidCellReference(reference)
                }
              None => (row, fallback_column.val)
            }
            fallback_column.val = column
            let style_id = integer_attribute(cell, "s", 2147483647)
            let warnings = []
            if styles_missing && style_id is Some(_) {
              warnings.push(MissingStylesPart)
            }
            let format_id = if styles_missing {
              None
            } else {
              match style_id {
                Some(id) if id < xfs.length() => Some(xfs[id])
                Some(id) => {
                  warnings.push(StyleIdOutOfRange(id))
                  None
                }
                None => None
              }
            }
            let code = match format_id {
              Some(id) =>
                match custom.get(id) {
                  Some(v) => Some(v)
                  None => builtin_format(id)
                }
              None => None
            }
            let (kind, malformed, ambiguous) = match (format_id, code) {
              (Some(id), Some(text)) => format_kind(id, text)
              (Some(id), None) => {
                warnings.push(UnsupportedNumberFormat(id, ""))
                (Unsupported, false, false)
              }
              _ => (General, false, false)
            }
            match (format_id, code) {
              (Some(id), Some(text)) => {
                if malformed {
                  warnings.push(UnsupportedNumberFormat(id, text))
                }
                if ambiguous {
                  warnings.push(AmbiguousNumberFormat(id, text))
                }
              }
              _ => ()
            }
            let formula = child_text(cell, "f")
            let raw = child_text(cell, "v")
            let resolved_text = match cell.attribute("t") {
              Some("inlineStr") =>
                match cell.first_child("is") {
                  Some(inline) => Some(descendant_text(inline))
                  None => None
                }
              Some("s") =>
                match raw {
                  Some(index_text) =>
                    match parse_decimal(index_text, strings.length()) {
                      Some(index) if index < strings.length() =>
                        Some(strings[index])
                      Some(index) => raise InvalidSharedStringIndex(index)
                      None =>
                        raise InvalidWorkbook(
                          "invalid shared string index: \{index_text}",
                        )
                    }
                  None => None
                }
              Some("str") => raw
              _ => None
            }
            let numeric = match (cell.attribute("t"), raw) {
              (None | Some("n"), Some(v)) =>
                try {
                  let parsed = @string.parse_double(v)
                  Some(parsed)
                } catch {
                  _ => None
                }
              _ => None
            }
            let converted = match numeric {
              Some(n) if kind == Date || kind == Time || kind == DateTime =>
                serial_metadata(n, date1904)
              _ => None
            }
            result.push({
              sheet_name: sheet.name,
              row: cell_row,
              column,
              raw_value: raw,
              resolved_text,
              formula,
              cached_value: if formula is Some(_) {
                raw
              } else {
                None
              },
              style_id,
              number_format_id: format_id,
              number_format: code,
              display_kind: kind,
              date_time: converted,
              warnings,
            })
          }
        }
      }
      None => continue
    }
  }
  result
}
