///|
/// Node adapter for MoonLeaf's neutral spreadsheet scene.
extern "js" fn read_file(path : String) -> FixedArray[Byte] = "(path) => Array.from(require('node:fs').readFileSync(path))"

///|
extern "js" fn write_file(path : String, bytes : FixedArray[Byte]) -> Unit = "(path, bytes) => require('node:fs').writeFileSync(path, Buffer.from(bytes), {flag: 'wx', mode: 0o600})"

///|
extern "js" fn read_stdin() -> String = "() => require('node:fs').readFileSync(0, 'utf8')"

///|
extern "js" fn report_error(message : String) -> Unit = "(message) => console.error(message)"

///|
fn cli_args() -> Array[String] {
  @env.args()
}
