///|
/// A failed compressed xref can prevent the ordinary reader from reaching the
/// text-stream recovery pass. Reconstruct only physical, syntactically complete
/// objects; use the publisher's trailer root, never infer a replacement catalog.
/// Stream bodies are skipped using the existing parser's exact byte length.
fn recover_metadata_document(
  data : Bytes,
) -> (@pdflite.PdfDocument, Array[Json]) raise PdfTextError {
  let version = @reader.pdf_read_header_from_view(data[:]) catch {
    error => raise InvalidPdf("Metadata recovery header: \{Repr(error)}")
  }
  let objects : Array[@syntax.PdfParsedIndirectObject] = []
  let trailers : Array[@syntax.PdfObject] = []
  let seen : Map[Int32, @syntax.PdfObject] = Map([])
  let classic_offsets = recover_classic_offsets(data[:])
  let mut position = 0
  while position < data.length() {
    // PDF comments and compressed/literal stream bytes are not object syntax.
    if data[position] == b'%' {
      while position < data.length() &&
            data[position] != b'\r' &&
            data[position] != b'\n' {
        position += 1
      }
    } else if @reader.pdf_reader_reconstruction_indirect_header_at(
        data[:],
        position,
      ) {
      let (parsed, next) = recover_physical_object(data[:], position) catch {
        error =>
          raise InvalidPdf(
            "Metadata recovery object at \{position}: \{Repr(error)}",
          )
      }
      // A linearized or incrementally saved PDF may retain earlier physical
      // versions. A successfully parsed current classic xref chain can select
      // its exact live offset even when accompanying compressed metadata fails.
      if classic_offsets.get(parsed.number) is Some(expected) &&
        expected != position {
        position = next
        continue
      }
      if seen.get(parsed.number) is Some(previous) && previous != parsed.object {
        // Without a trustworthy xref, a different revision of an object must
        // not silently replace one another according to scan order.
        raise InvalidPdf(
          "Cannot recover ambiguous object \{parsed.number} revisions without xref metadata",
        )
      }
      seen[parsed.number] = parsed.object
      objects.push(parsed)
      if objects.length() > 200_000 {
        raise TooLarge
      }
      if parsed.object is PdfStreamObject(stream) &&
        stream.dictionary.lookup_immediate(name(b"/Type")) ==
        Some(PdfNameObject(name(b"/XRef"))) {
        trailers.push(
          @reader.pdf_reader_stream_dictionary_without_xref_keys(
            stream.dictionary,
          ) catch {
            error =>
              raise InvalidPdf(
                "Metadata recovery xref dictionary: \{Repr(error)}",
              )
          },
        )
      }
      position = next
    } else if @pdfcore.pdf_view_matches_ascii_at(data[:], position, [
        116, 114, 97, 105, 108, 101, 114,
      ]) {
      let cursor = @pdfcore.byte_cursor_of_view(data[:])
      let trailer = try {
        cursor.seek_absolute(position)
        @reader.pdf_cursor_read_trailer_dictionary(cursor)
      } catch {
        error => raise InvalidPdf("Metadata recovery trailer: \{Repr(error)}")
      }
      trailers.push(trailer)
      position = cursor.absolute_position()
    } else {
      position += 1
    }
  }
  if objects.is_empty() || trailers.is_empty() {
    raise InvalidPdf(
      "No complete physical objects and original trailer for metadata recovery",
    )
  }
  let mut root : Int32? = None
  let mut trailer : @syntax.PdfObject? = None
  for candidate in trailers {
    if candidate.lookup_immediate(name(b"/Encrypt")) is Some(value) &&
      !(value is PdfNull) {
      raise Encrypted
    }
    if candidate.lookup_immediate(name(b"/Root")) is Some(PdfIndirect(number)) {
      if root is Some(previous) && previous != number {
        raise InvalidPdf("Cannot recover conflicting trailer roots")
      }
      root = Some(number)
      trailer = Some(candidate)
    }
  }
  guard root is Some(root_number) && trailer is Some(original_trailer) else {
    raise InvalidPdf(
      "Original root reference is unavailable for metadata recovery",
    )
  }
  let document = @pdflite.pdf_document_of_parsed_indirect_objects(
    objects[:],
    version~,
  )
  document.set_root(root_number)
  document.set_trailer_dict(original_trailer)
  let warnings = recover_document_text_streams(
    document,
    restore_object_streams=true,
  )
  guard document
    .lookup_object_or_null(root_number)
    .lookup_immediate(name(b"/Type")) ==
    Some(PdfNameObject(name(b"/Catalog"))) else {
    raise InvalidPdf("Recovered original root is not a catalog")
  }
  warnings.push({
    "code": "source_xref_metadata_reconstructed",
    "message": "Strict compressed metadata decoding failed. The original trailer root and complete physical objects were recovered with existing PDF syntax parsers. Xref checksum remains unverified; original source bytes were not rewritten.",
    "physical_object_count": objects.length(),
    "root_object_number": root_number,
  })
  (document, warnings)
}

///|
fn recover_classic_offsets(data : BytesView) -> Map[Int32, Int32] {
  let offsets : Map[Int32, Int32] = Map([])
  let seen : Map[Int32, Bool] = Map([])
  let positions : Map[Int32, Bool] = Map([])
  try {
    let mut position = @reader.pdf_read_startxref_position(data)
    for ;; {
      if positions.contains(position) {
        return Map([])
      }
      positions[position] = true
      let cursor = @pdfcore.byte_cursor_of_view(data)
      cursor.seek_absolute(position)
      let entries = @reader.pdf_cursor_read_classic_xref_entries(cursor)
      for entry in entries {
        if !seen.contains(entry.object_number) {
          seen[entry.object_number] = true
          if entry.in_use && entry.object_stream is None {
            offsets[entry.object_number] = entry.offset
          }
        }
      }
      let trailer = @reader.pdf_cursor_read_trailer_dictionary(cursor)
      match @reader.pdf_trailer_prev_position(trailer) {
        Some(previous) => position = previous
        None => return offsets
      }
    }
  } catch {
    // No partially read chain is authoritative for resolving duplicate objects.
    _ => Map([])
  }
}

///|
fn recover_physical_object(
  data : BytesView,
  start : Int32,
) -> (@syntax.PdfParsedIndirectObject, Int32) raise @pdfcore.PdfError {
  let mut search = start
  for ;; {
    let endobj = @pdfcore.pdf_find_ascii_from(data, search, [
      101, 110, 100, 111, 98, 106,
    ])
    if endobj < 0 {
      raise ParseEndObjectExpected
    }
    let cursor = @pdfcore.byte_cursor_of_view(data[start:endobj + 6])
    let tokens = @syntax.pdf_cursor_lex_tokens(cursor) catch {
      _ => {
        search = endobj + 6
        continue
      }
    }
    let (prefix, _, complete) = @syntax.pdf_parse_indirect_object_segment_at(
      tokens[:],
      0,
    )
    if complete {
      return (prefix, endobj + 6)
    }
    let stream_position = start + cursor.absolute_position()
    let parsed = @pdflite.pdf_parse_stream_object_from_view(data[start:])
    let stream_data = parsed.object.stream_bytes()
    let tail = @pdfcore.byte_cursor_of_view(data)
    tail.seek_absolute(stream_position)
    @reader.pdf_cursor_consume_ascii(
      tail,
      [115, 116, 114, 101, 97, 109],
      ParseStreamExpected,
    )
    // The PDF stream keyword is followed by LF or CRLF (some producers use CR).
    if tail.peek_byte() == 13 {
      tail.nudge()
    }
    if tail.peek_byte() == 10 {
      tail.nudge()
    }
    tail.seek_absolute(tail.absolute_position() + stream_data.length())
    @syntax.pdf_cursor_drop_whitespace(tail)
    @reader.pdf_cursor_consume_ascii(
      tail,
      [101, 110, 100, 115, 116, 114, 101, 97, 109],
      ParseEndStreamExpected,
    )
    @syntax.pdf_cursor_drop_whitespace(tail)
    @reader.pdf_cursor_consume_ascii(
      tail,
      [101, 110, 100, 111, 98, 106],
      ParseEndObjectExpected,
    )
    return (parsed, tail.absolute_position())
  }
}
