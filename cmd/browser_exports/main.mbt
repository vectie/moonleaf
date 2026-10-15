///|
extern "js" fn publish(export_json : (String) -> String) -> Unit =
  #| (export_json) => { globalThis.MoonLeafBrowserExports = { export_json }; }

///|
fn main {
  publish(@exports.export_json)
}
