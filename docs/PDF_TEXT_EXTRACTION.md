# PDF text extraction

`pdf_text.extract_with_details` returns extracted Markdown, structured
`extraction_warnings`, `checksum_verification`, and `truncated_pages`.
The existing `extract` method returns the same text for compatibility.
The `preview extract-pdf SOURCE OUTPUT [MAX_BYTES]` command writes the text file
and prints a `moonleaf.pdf-text-extraction.v1` JSON receipt with this metadata.

The source file budget remains at most 32 MiB, extraction is limited to the first
100 pages, and output text to one million characters. No OCR is performed.

## Damaged source Flate checksums

Some actual issuer reports contain complete DEFLATE bodies whose zlib trailers
are missing bytes or fail checksum verification. Version 0.1.49 adds recovery
specifically for PDF text extraction. The ordinary pdflite decoder stays strict.

Recovery considers non-image streams with a single Flate filter and no predictor.
It requires a valid zlib header, no preset dictionary, a fully completed raw
DEFLATE body, at most four remaining trailer bytes, and bounded output. An
incomplete or malformed raw body still fails extraction. Each recovered stream is
limited to 8 MiB; total recovered stream output is limited to 32 MiB.

The decoder does not manufacture a checksum or claim source verification. The
receipt records `source_zlib_checksum_unverified`, the original object number,
compressed byte count, consumed raw-body bytes and remaining trailer bytes.
`checksum_verification` is `unverified_recovered_streams` when recovery occurs.
The extracted text also includes an explicit source warning. Consumers should
retain this metadata alongside quotations and extracted facts.

If the source parser skipped compressed resource dictionaries because their
object-stream checksum failed, extraction restores only missing original members
from the fully recovered object-stream body. It uses pdflite's existing member
offset parser and PDF object parser, checks each member boundary, and preserves
existing objects. The receipt records `source_object_stream_members_recovered`.
This restores actual source font resources without inventing font mappings.

This repair was applied to the actual Tencent 2026 interim and 2025 annual
reports acquired from HKEXnews. The interim report included a 2,133-byte source
stream whose zlib trailer was incomplete. Recovery used its fully completed raw
body and kept the source checksum unverified. No synthetic PDF or test suite was
used for this change.
