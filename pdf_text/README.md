# PDF text extraction

MoonLeaf uses pdflite's strict document reader first. Text extraction is bounded
by source bytes, page range and output size; it does not perform OCR.

## Damaged compressed metadata (0.1.53)

Some saved Tencent HKEX PDFs fail with `InvalidFlateData` while loading xref or
object-stream metadata, before the existing text-stream recovery can run.
MoonLeaf now reconstructs complete physical objects using pdflite's syntax
parsers and the original trailer's catalog reference. It skips compressed
payloads using the stream parser's byte length. A fully readable classic xref
chain selects live physical offsets; ambiguous object revisions or conflicting
catalog roots remain errors. Encrypted documents remain unsupported.

Missing compressed dictionaries are restored from complete original object
streams. Raw DEFLATE recovery still requires a valid zlib header and a completed,
bounded body. Source bytes and checksums are never rewritten. Receipts retain
`source_zlib_checksum_unverified`, `source_object_stream_members_recovered` and
`source_xref_metadata_reconstructed` warnings and report
`checksum_verification: "unverified_recovered_streams"`.

The actual saved Tencent 2024 Q1 report's requested pages 14–18 were acquired
successfully with this recovery path (48 pages total, 10,560 restored compressed
resource objects). The saved 2023 annual report exposed differing physical
revisions, prompting the classic-xref offset selection above; no additional
extraction or test suite was run after that change. Source warning receipts must
remain attached to downstream text/citations.
