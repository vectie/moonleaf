# PPTX implementation provenance

MoonLeaf's PresentationML reader and conservative text replacement are original
MoonBit implementations based on the ECMA-376 package and PresentationML model.

The package architecture and supported shape vocabulary were informed by
[PptxGenJS](https://github.com/gitbrent/PptxGenJS), an MIT-licensed JavaScript
project. No PptxGenJS source code is copied or bundled. PptxGenJS remains an
upstream behavioral reference for future compatibility fixtures.

The implementation intentionally stays below a full rendering engine: it reads
presentation order and size, text runs, preset shapes, pictures, and transforms,
and it edits only exact `a:t` payloads while preserving unrelated package parts.
