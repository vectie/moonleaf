///|
fn create_pptx_file(args : Array[String]) -> Unit {
  guard args.length() == 4 else {
    abort("usage: moonleaf-preview create-pptx OUTPUT")
  }
  let raw = read_stdin()
  guard raw.length() <= 4_194_304 else {
    abort("PPTX JSON exceeds 4 Mi UTF-16 units")
  }
  let input = @json.parse(raw) catch {
    _ => abort("invalid PPTX creation JSON")
  }
  let bytes = @pptx.create(input) catch {
    error => abort("MoonLeaf PPTX creation failed: \{Repr(error)}")
  }
  write_file(args[3], bytes)
  let slides = match input {
    { "slides": Array(slides), .. } => slides.length()
    _ => 0
  }
  let receipt : Json = {
    "contract": "moonleaf.pptx-create.v1",
    "slides": slides,
    "bytes": bytes.length(),
  }
  println(receipt.stringify())
}
