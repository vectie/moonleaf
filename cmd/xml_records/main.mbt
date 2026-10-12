///|
/// Reads a bounded UTF-8 stream before calling the pure XML adapter. A fatal
/// decoder rejects malformed bytes rather than silently inserting replacements.
extern "js" fn read_utf8(path : String, limit : Int) -> String =
  #|(path, limit) => {
  #|  const fs = require('node:fs');
  #|  const fd = path === '-' ? 0 : fs.openSync(path, 'r');
  #|  try {
  #|    const chunks = []; let total = 0;
  #|    while (true) {
  #|      const buffer = Buffer.alloc(Math.min(65536, limit + 1 - total));
  #|      const count = fs.readSync(fd, buffer, 0, buffer.length, null);
  #|      if (!count) break;
  #|      total += count;
  #|      if (total > limit) throw new Error('UTF-8 input exceeds byte limit');
  #|      chunks.push(buffer.subarray(0, count));
  #|    }
  #|    return new TextDecoder('utf-8', {fatal: true}).decode(Buffer.concat(chunks));
  #|  } finally { if (fd !== 0) fs.closeSync(fd); }
  #|}

///|
extern "js" fn write_bytes(bytes : FixedArray[Byte]) -> Unit = "bytes => require('node:fs').writeFileSync(1, Buffer.from(bytes))"

///|
extern "js" fn report_error(message : String) -> Unit = "message => { console.error(message); process.exitCode = 1; }"

///|
fn run() -> Unit raise {
  let args = @env.args()
  guard args.length() == 4 && ["csv", "json", "xlsx"].contains(args[3]) else {
    fail(
      "usage: node xml_records.js MAPPING.json csv|json|xlsx < INPUT.xml > COPY",
    )
  }
  let spec = @jsontable.parse_xml_spec(read_utf8(args[2], 262144))
  let table = @jsontable.parse_xml_records(read_utf8("-", 4000000), spec)
  // Export succeeds in memory before any data is emitted to stdout.
  match args[3] {
    "xlsx" => write_bytes(table.export_xlsx())
    "csv" => println(table.export_csv().trim_end(chars="\r\n"))
    _ => println(table.export_json(omit_empty=true))
  }
}

///|
fn main {
  run() catch {
    error => report_error("MoonLeaf XML intake failed: \{Repr(error)}")
  }
}
