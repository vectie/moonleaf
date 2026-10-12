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
    "Only direct w:r/w:t text in main-body paragraphs and one-level table cells is selectable; wrappers, hyperlinks, drawings, nested tables, headers and footers are omitted.",
    "Target IDs belong to the exact source SHA-256 and must be inspected again after any source change.",
    "Copy verification checks supported scene and package payloads, not Office layout fidelity, print readiness, delivery or acceptance.",
  ]
}

///|
fn run() -> Unit raise {
  let args = @env.args()
  guard (args.length() == 4 && args[2] == "inspect") ||
    (args.length() == 6 && args[2] == "apply") else {
    fail(
      "usage: node docx-edit.js inspect SOURCE.docx | apply SOURCE.docx REQUEST.json FRESH_COPY.docx",
    )
  }
  let source = read_bytes(args[3], 8_388_608)
  let digest = sha256(source)
  let session = @moonleaf.open_session_with_policy(
    "source.docx",
    source,
    limits(),
  )
  if args[2] == "inspect" {
    let targets = session
      .docx_text_targets()
      .map(target => {
        let item : Json = { "id": target.id, "text": target.text }
        item
      })
    let report : Json = {
      "schema": "moonleaf.docx-text-targets.v1",
      "source_sha256": digest,
      "targets": targets,
      "warnings": warnings(),
    }
    println(report.stringify())
    return
  }
  let request_text = @utf8.decode(
    Bytes::from_array(read_bytes(args[4], 65_536)),
  )
  let request = @json.parse(request_text)
  guard request is Object(fields) &&
    fields.length() == 5 &&
    request
    is {
      "version": Number(1, ..),
      "source_sha256": String(expected_digest),
      "target": String(id),
      "expected": String(expected),
      "replacement": String(replacement),
      ..
    } else {
    fail(
      "request requires exactly version:1, source_sha256, target, expected and replacement",
    )
  }
  if expected_digest != digest {
    fail("source SHA-256 differs from inspected source; inspect again")
  }
  let changed = session.set_docx_target_text(id, expected, replacement)
  let copy = changed.save_as_copy()
  let bytes = copy.bytes()
  // Reopen the exact emitted bytes and inspect the chosen target, in addition to
  // DocumentSession's supported-scene and all-package-payload verification.
  let reopened = @moonleaf.open_session_with_policy(
    "copy.docx",
    bytes,
    limits(),
  )
  let matches = reopened.docx_text_targets().filter(target => target.id == id)
  guard matches is [target] && target.text == replacement else {
    fail("chosen text target changed during copy reopen")
  }
  write_copy(args[5], bytes)
  let report : Json = {
    "schema": "moonleaf.docx-text-copy.v1",
    "source_sha256": digest,
    "copy_sha256": sha256(bytes),
    "target": id,
    "before": expected,
    "after": replacement,
    "changed": expected != replacement,
    "reopened": true,
    "readback_equal": true,
    "warnings": warnings(),
  }
  println(report.stringify())
}

///|
fn main {
  run() catch {
    error => report_error("MoonLeaf targeted DOCX edit failed: \{Repr(error)}")
  }
}
