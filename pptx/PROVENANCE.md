# PPTX implementation provenance

MoonLeaf's PresentationML reader and conservative text replacement implement
the ECMA-376 package and PresentationML model in MoonBit.

The package architecture and supported shape vocabulary were informed by
[PptxGenJS](https://github.com/gitbrent/PptxGenJS), an MIT-licensed JavaScript
project. The baseline did not record the exact upstream revision or files
consulted, so both remain unknown. No claim about copied code is made.
PptxGenJS remains acknowledged as a behavioral and architectural reference; its
canonical MIT notice is reproduced in the repository-level `NOTICE`.

The implementation intentionally stays below a full rendering engine: it reads
presentation order and size, text runs, preset shapes, pictures, and transforms,
and it edits only exact `a:t` payloads while preserving unrelated package parts.
