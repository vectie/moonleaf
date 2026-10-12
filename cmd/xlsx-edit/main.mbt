///|
extern "js" fn read_bytes(path : String, limit : Int) -> FixedArray[Byte] =
  #|(path, limit) => { const fs = require('node:fs'); const fd = fs.openSync(path, fs.constants.O_RDONLY | fs.constants.O_NONBLOCK); try { const stat = fs.fstatSync(fd); if (!stat.isFile() || stat.size > limit) throw Error('Expected a bounded regular file'); const bytes = fs.readFileSync(fd); if (bytes.length > limit) throw Error('Input exceeds byte limit'); return Array.from(bytes); } finally { fs.closeSync(fd); } }

///|
extern "js" fn sha256(bytes : FixedArray[Byte]) -> String =
  #|bytes => require('node:crypto').createHash('sha256').update(Buffer.from(bytes)).digest('hex')

///|
extern "js" fn write_copy(path : String, bytes : FixedArray[Byte]) -> Unit =
  #|(path, bytes) => { const fs = require('node:fs'); const content = Buffer.from(bytes); fs.writeFileSync(path, content, {flag:'wx', mode:0o600}); if (!fs.readFileSync(path).equals(content)) throw Error('Written copy readback differs from verified bytes'); }

///|
extern "js" fn report_error(message : String) -> Unit =
  #|message => { console.error(message); process.exitCode = 1; }

///|
fn limits() -> @opc.ArchivePolicy {
  {
    ..@opc.ArchivePolicy::default(),
    max_compressed_input_bytes: 8_388_608,
    max_entry_compressed_bytes: 8_388_608,
    max_entry_uncompressed_bytes: 8_388_608,
    max_total_uncompressed_bytes: 16_777_216,
  }
}

///|
fn warnings() -> Array[String] {
  [
    "Only existing unmerged ordinary inline/shared text cells are editable. Rich text, formulas and formula-result ranges are refused.",
    "Formula expressions and stored caches are retained, not recalculated. Text corrections can make dependent calculations stale; no freshness is asserted.",
    "Cell style identifiers and unrelated package payloads are retained; copy verification does not establish Excel visual fidelity, print readiness, delivery or acceptance.",
    "Source digests and expected values identify the read snapshot. Inspect again after source changes; hosts own permissions, source retention and destination conflicts.",
  ]
}

///|
fn target_json(target : @xlsx.TextCellTarget) -> Json {
  let style : Json = match target.style_id {
    Some(value) => value.to_json()
    None => Json::null()
  }
  {
    "sheet": target.sheet,
    "address": target.address,
    "text": target.text,
    "style_id": style,
  }
}

///|
fn run() -> Unit raise {
  let args = @env.args()
  guard (args.length() >= 6 && args.length() <= 105 && args[2] == "inspect") ||
    (args.length() == 6 && args[2] == "apply") else {
    fail(
      "usage: node xlsx-edit.js inspect SOURCE.xlsx SHEET A1 [B2 ...] | apply SOURCE.xlsx REQUEST.json FRESH_COPY.xlsx",
    )
  }
  let source = read_bytes(args[3], 8_388_608)
  let digest = sha256(source)
  let archive = @opc.open_with_policy(source, limits())
  // Bound and disambiguate the supported workbook comparison before editing.
  let _ = @xlsx.compare_workbooks(archive, archive)
  if args[2] == "inspect" {
    let targets = []
    for i = 5; i < args.length(); i = i + 1 {
      targets.push(
        target_json(
          @xlsx.inspect_text_cell(archive, sheet_name=args[4], address=args[i]),
        ),
      )
    }
    let report : Json = {
      "schema": "moonleaf.xlsx-text-targets.v1",
      "source_sha256": digest,
      "targets": targets,
      "warnings": warnings(),
    }
    println(report.stringify())
    return
  }
  let request = @json.parse(
    @utf8.decode(Bytes::from_array(read_bytes(args[4], 1_048_576))),
  )
  guard request is Object(fields) &&
    fields.length() == 3 &&
    request
    is {
      "version": Number(1, ..),
      "source_sha256": String(expected_digest),
      "edits": Array(items),
      ..
    } else {
    fail("request requires exactly version:1, source_sha256 and edits")
  }
  if expected_digest != digest {
    fail("source SHA-256 differs from inspected source; inspect again")
  }
  let edits : Array[@xlsx.TextCellCorrection] = []
  for item in items {
    guard item is Object(fields) &&
      fields.length() == 4 &&
      item
      is {
        "sheet": String(sheet),
        "address": String(address),
        "expected": String(expected),
        "replacement": String(replacement),
        ..
      } else {
      fail(
        "each edit requires exactly sheet, address, expected and replacement strings",
      )
    }
    edits.push({ sheet, address, expected, replacement, })
  }
  let session = @moonleaf.open_session_with_policy(
    "source.xlsx",
    source,
    limits(),
  )
  let changed = session.correct_xlsx_text_cells(edits)
  let verified = changed.save_as_copy()
  let bytes = verified.bytes()
  let reopened = @opc.open_with_policy(bytes, limits())
  for edit in edits {
    let target = @xlsx.inspect_text_cell(
      reopened,
      sheet_name=edit.sheet,
      address=edit.address,
    )
    if target.text != edit.replacement {
      fail("corrected cell differs after copy reopen")
    }
  }
  let comparison = @xlsx.compare_workbooks(archive, reopened)
  write_copy(args[5], bytes)
  let report : Json = {
    "schema": "moonleaf.xlsx-text-copy.v1",
    "source_sha256": digest,
    "copy_sha256": sha256(bytes),
    "request": request,
    "requested_cells": edits.length(),
    "changed_cells": comparison.changed_cells,
    "comparison": comparison.to_json(),
    "reopened": true,
    "readback_equal": true,
    "warnings": warnings(),
    "diagnostics": verified
    .session()
    .diagnostics()
    .map(d => {
      let part : Json = match d.part {
        Some(value) => value.to_json()
        None => Json::null()
      }
      let item : Json = { "code": d.code, "message": d.message, "part": part }
      item
    }),
  }
  println(report.stringify())
}

///|
fn main {
  run() catch {
    error =>
      report_error("MoonLeaf XLSX text correction failed: \{Repr(error)}")
  }
}
