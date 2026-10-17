///|
/// Extraction metadata keeps source checksum failures visible to callers.
pub(all) struct PdfTextResult {
  text : String
  extraction_warnings : Array[Json]
  checksum_verification : String
  truncated_pages : Bool
} derive(ToJson)

///|
pub extend PdfTextResult with ToJson::{to_json}

///|
fn name(text : Bytes) -> @pdfcore.PdfName {
  @pdfcore.pdf_name_of_bytes(text)
}

///|
/// Recover only a fully terminated raw DEFLATE body behind a valid zlib header.
/// The original checksum is explicitly unverified; no replacement checksum is
/// manufactured. Text recovery never changes the normal PDF stream decoder.
fn recover_text_flate(data : Bytes) -> (Bytes, Int32, Int32) raise PdfTextError {
  if data.length() < 3 {
    raise InvalidPdf("Incomplete zlib header")
  }
  let cmf = data[0].to_int()
  let flg = data[1].to_int()
  if (cmf & 15) != 8 ||
    cmf >> 4 > 7 ||
    (cmf * 256 + flg) % 31 != 0 ||
    (flg & 32) != 0 {
    raise InvalidPdf("Invalid or dictionary-dependent zlib header")
  }
  let decoder = @flate.Inflater()
  let scratch = FixedArray::make(32768, b'\x00')
  let output = @buffer.Buffer()
  let mut position = 2
  for ;; {
    let status = decoder.step(data[position:], scratch.mut_view(), end=true) catch {
      _ => raise InvalidPdf("Source DEFLATE body is incomplete or malformed")
    }
    let used = decoder.last_consumed()
    let produced = decoder.last_produced()
    if produced > 8 * 1024 * 1024 - output.length() {
      raise TooLarge
    }
    for i in 0..<produced {
      output.write_byte(scratch[i])
    }
    position += used
    match status {
      Done => {
        let trailer = data.length() - position
        if trailer < 0 || trailer > 4 {
          raise InvalidPdf("Unexpected bytes after source DEFLATE body")
        }
        return (output.to_bytes(), position - 2, trailer)
      }
      NeedMoreInput =>
        raise InvalidPdf("Source DEFLATE body does not terminate")
      NeedMoreOutput =>
        if used == 0 && produced == 0 {
          raise InvalidPdf("Source DEFLATE decoder made no progress")
        }
    }
  }
}

///|
fn recover_document_text_streams(
  document : @pdflite.PdfDocument,
) -> Array[Json] raise PdfTextError {
  let warnings : Array[Json] = []
  let recovered_members : Array[(Int32, @syntax.PdfObject)] = []
  let mut total_recovered = 0
  document.iter_objects((object_number, object) => {
    guard object is PdfStreamObject(stream) else { return }
    let dictionary = stream.dictionary
    // Raster images are irrelevant to text extraction and can be very large.
    if dictionary.lookup_immediate(name(b"/Subtype")) is Some(PdfNameObject(v)) &&
      v == name(b"/Image") {
      return
    }
    let is_flate = match dictionary.lookup_immediate(name(b"/Filter")) {
      Some(PdfNameObject(v)) => v == name(b"/FlateDecode") || v == name(b"/Fl")
      Some(PdfArray([PdfNameObject(v)])) =>
        v == name(b"/FlateDecode") || v == name(b"/Fl")
      _ => false
    }
    if !is_flate {
      return
    }
    // Predictor and chained filters require their own semantics; never guess.
    if dictionary.lookup_immediate(name(b"/DecodeParms")) is Some(value) &&
      !(value is PdfNull) {
      return
    }
    let failed = try {
      ignore(@pdflite.pdf_decode_stream(object))
      false
    } catch {
      InvalidFlateData => true
      _ => false
    }
    if !failed {
      return
    }
    let data = object.stream_bytes() catch {
      _ => raise InvalidPdf("Cannot read source text stream")
    }
    let (decoded, consumed, trailer) = recover_text_flate(data)
    total_recovered += decoded.length()
    if total_recovered > 32 * 1024 * 1024 {
      raise TooLarge
    }
    stream.dictionary = dictionary
      .remove_dict_entry(name(b"/Filter"))
      .remove_dict_entry(name(b"/DecodeParms"))
      .replace_dict_entry(name(b"/Length"), PdfInteger(decoded.length())) catch {
        _ => raise InvalidPdf("Cannot preserve recovered source text stream")
      }
    stream.data = StreamGot(decoded)
    warnings.push({
      "code": "source_zlib_checksum_unverified",
      "object_number": object_number,
      "message": "Source zlib stream failed strict verification. Complete bounded raw DEFLATE body recovered for text extraction only; checksum not verified or fabricated.",
      "compressed_bytes": data.length(),
      "deflate_bytes_consumed": consumed,
      "trailer_bytes": trailer,
    })
    // Reconstructed documents can have skipped compressed font/resource
    // dictionaries when the original object-stream checksum failed. Restore
    // only genuinely absent members using the existing object-stream parser.
    if dictionary.lookup_immediate(name(b"/Type")) is Some(PdfNameObject(kind)) &&
      kind == name(b"/ObjStm") {
      let first = match dictionary.lookup_immediate(name(b"/First")) {
        Some(PdfInteger(v)) => v
        _ => raise InvalidPdf("Object stream lacks First offset")
      }
      let count = match dictionary.lookup_immediate(name(b"/N")) {
        Some(PdfInteger(v)) => v
        _ => raise InvalidPdf("Object stream lacks member count")
      }
      let pairs = @reader.pdf_object_stream_number_offsets(
        decoded[:],
        first,
        count,
      )
      let ends = @reader.pdf_object_stream_end_offsets(
        pairs[:],
        decoded.length(),
        first,
      )
      for i, (member_number, offset) in pairs {
        if document.lookup_object_or_null(member_number) is PdfNull {
          let begin = first + offset
          let end = first + ends[i]
          if begin < first || end < begin || end > decoded.length() {
            raise InvalidPdf("Invalid source object stream member bounds")
          }
          let parsed_member = @syntax.pdf_parse_object_from_view(
            decoded[begin:end],
          )
          recovered_members.push((member_number, parsed_member))
        }
      }
    }
  }) catch {
    error => raise InvalidPdf("\{Repr(error)}")
  }
  for (number, object) in recovered_members {
    if document.lookup_object_or_null(number) is PdfNull {
      document.add_object_given_number(number, object)
    }
  }
  if !recovered_members.is_empty() {
    warnings.push({
      "code": "source_object_stream_members_recovered",
      "message": "Missing compressed resource dictionaries restored from complete recovered original object-stream bodies; no font mappings inferred.",
      "member_count": recovered_members.length(),
    })
  }
  warnings
}
