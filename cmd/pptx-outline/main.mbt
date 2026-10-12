///|
extern "js" fn read_bytes(path : String, limit : Int) -> FixedArray[Byte] =
  #|(path, limit) => { const fs = require('node:fs'); const fd = fs.openSync(path, fs.constants.O_RDONLY | fs.constants.O_NONBLOCK); try { const stat = fs.fstatSync(fd); if (!stat.isFile() || stat.size > limit) throw Error('Expected a bounded regular file'); const bytes = fs.readFileSync(fd); if (bytes.length > limit) throw Error('Input exceeds byte limit'); return Array.from(bytes); } finally { fs.closeSync(fd); } }

///|
extern "js" fn source_uri(path : String) -> String =
  #|path => require('node:url').pathToFileURL(require('node:fs').realpathSync(path)).href

///|
extern "js" fn sha256(bytes : FixedArray[Byte]) -> String =
  #|bytes => require('node:crypto').createHash('sha256').update(Buffer.from(bytes)).digest('hex')

///|
extern "js" fn write_copy(path : String, bytes : FixedArray[Byte]) -> Unit =
  #|(path, bytes) => { const fs = require('node:fs'); const content = Buffer.from(bytes); fs.writeFileSync(path, content, {flag:'wx', mode:0o600}); if (!fs.readFileSync(path).equals(content)) throw Error('Written outline readback differs from expected bytes'); }

///|
extern "js" fn report_error(message : String) -> Unit =
  #|message => { console.error(message); process.exitCode = 1; }

///|
fn run() -> Unit raise {
  let args = @env.args()
  guard (args.length() == 4 && args[2] == "inspect") ||
    (
      args.length() == 6 &&
      args[2] == "export" &&
      (args[4] == "json" || args[4] == "markdown")
    ) else {
    fail(
      "usage: node pptx-outline.js inspect SOURCE.pptx | export SOURCE.pptx json|markdown FRESH_OUTPUT",
    )
  }
  let source = read_bytes(args[3], 8_388_608)
  let digest = sha256(source)
  let uri = source_uri(args[3])
  let policy : @opc.ArchivePolicy = {
    ..@opc.ArchivePolicy::default(),
    max_compressed_input_bytes: 8_388_608,
    max_entry_compressed_bytes: 8_388_608,
    max_entry_uncompressed_bytes: 8_388_608,
    max_total_uncompressed_bytes: 16_777_216,
  }
  let outline = @pptx.read_outline(@opc.open_with_policy(source, policy))
  let report : Json = {
    "schema": "moonleaf.presentation-outline.v1",
    "source_sha256": digest,
    "source_uri": uri,
    "outline": outline,
  }
  if args[2] == "inspect" {
    println(report.stringify())
    return
  }
  let content = if args[4] == "json" {
    report.stringify() + "\n"
  } else {
    "Original: [PPTX source](<\{uri}>)\n\nSource SHA-256: \{digest}\n\n" +
    outline.to_markdown()
  }
  let output = @utf8.encode(content).to_fixedarray()
  write_copy(args[5], output)
  let result : Json = {
    "schema": "moonleaf.presentation-outline-export.v1",
    "source_sha256": digest,
    "output_sha256": sha256(output),
    "format": args[4],
    "slides": outline.slides.length(),
    "readback_equal": true,
  }
  println(result.stringify())
}

///|
fn main {
  run() catch {
    error =>
      report_error("MoonLeaf presentation outline failed: \{Repr(error)}")
  }
}
