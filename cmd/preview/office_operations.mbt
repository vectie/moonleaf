///|
fn preview_pptx(args : Array[String]) -> Unit {
  if args.length() != 4 {
    abort("usage: moonleaf-preview preview-pptx SOURCE")
  }
  let bytes = read_file(args[3])
  let container = @opc.open(bytes) catch {
    error => abort("PPTX open failed: \{Repr(error)}")
  }
  let preview = @pptx.preview_json(container, @pptx.source_sha256(bytes)) catch {
    error => abort("PPTX preview failed: \{Repr(error)}")
  }
  println(preview.stringify())
}

///|
fn extract_pptx(args : Array[String]) -> Unit {
  if args.length() != 5 {
    abort("usage: moonleaf-preview extract-pptx SOURCE OUTPUT")
  }
  let container = @opc.open(read_file(args[3])) catch {
    error => abort("PPTX open failed: \{Repr(error)}")
  }
  let text = @pptx.plain_text(container) catch {
    error => abort("PPTX extraction failed: \{Repr(error)}")
  }
  write_file(args[4], @utf8.encode(text).to_fixedarray())
}

///|
fn edit_pptx_copy(args : Array[String]) -> Unit {
  if args.length() != 5 {
    abort("usage: moonleaf-preview edit-pptx-copy SOURCE OUTPUT")
  }
  let request = @json.parse(read_stdin()) catch {
    _ => abort("invalid PPTX edit JSON")
  }
  let (copy, receipt) = @pptx.edit_copy(read_file(args[3]), request) catch {
    error => abort("PPTX edit failed: \{Repr(error)}")
  }
  write_file(args[4], copy)
  println(receipt.stringify())
}

///|
fn edit_docx_structure_copy(args : Array[String]) -> Unit {
  if args.length() != 5 {
    abort("usage: moonleaf-preview edit-docx-structure-copy SOURCE OUTPUT")
  }
  let request = @json.parse(read_stdin()) catch {
    _ => abort("invalid DOCX operation JSON")
  }
  let source = read_file(args[3])
  if source.length() > 16_777_216 {
    abort("DOCX source exceeds 16MiB")
  }
  let container = @opc.open(source) catch {
    error => abort("DOCX open failed: \{Repr(error)}")
  }
  let edited = @docx.edit_body_paragraph(container, request) catch {
    error => abort("DOCX operation failed: \{Repr(error)}")
  }
  let changed = edited != container
  let copy = if changed {
    @opc.save(edited) catch {
      error => abort("DOCX save failed: \{Repr(error)}")
    }
  } else {
    source
  }
  let paragraph_count = @docx.preview_document(edited) catch {
    error => abort("DOCX paragraph count unavailable: \{Repr(error)}")
  }
  let count = paragraph_count.blocks
    .filter(block => block is FlowParagraph(_))
    .length()
  write_file(args[4], copy)
  let receipt : Json = {
    "contract": "moonleaf.docx-structure-copy.v1",
    "changed": changed,
    "bytes": copy.length(),
    "paragraph_count": count,
  }
  println(receipt.stringify())
}

///|
fn docx_flow_block_json(
  block : @docx.DocxFlowBlock,
  text_size : Ref[Int],
  paragraph_index : Ref[Int],
  table_index? : Ref[Int],
) -> Json {
  match block {
    FlowParagraph(paragraph) => {
      let value = docx_paragraph_json(paragraph, text_size)
      guard value is Object(fields) else {
        abort("DOCX paragraph JSON unavailable")
      }
      fields["paragraph_index"] = paragraph_index.val.to_json()
      paragraph_index.val += 1
      Json::object(fields)
    }
    FlowTable(table) =>
      match table_index {
        Some(index) => {
          let value = docx_table_json(table, text_size, table_index=index.val)
          index.val += 1
          value
        }
        None => docx_table_json(table, text_size)
      }
    FlowPageBreak => { "type": "page_break" }
    FlowSection(section) =>
      {
        "type": "section",
        "page_width_twips": optional_int_json(section.page_width_twips),
        "page_height_twips": optional_int_json(section.page_height_twips),
        "margin_top_twips": optional_int_json(section.margin_top_twips),
        "margin_right_twips": optional_int_json(section.margin_right_twips),
        "margin_bottom_twips": optional_int_json(section.margin_bottom_twips),
        "margin_left_twips": optional_int_json(section.margin_left_twips),
      }
  }
}
