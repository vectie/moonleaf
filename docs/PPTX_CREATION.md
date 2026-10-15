# New editable PPTX creation

MoonLeaf **0.1.40** adds `vectie/moonleaf/pptx.create(Json) -> FixedArray[Byte]
raise PptxError`. It creates a new standalone PresentationML package through
the existing MoonBit OPC/ZIP writer. No JavaScript or Python assembles the
document; the CLI's existing adapter only reads stdin and writes file bytes.

## Input

```json
{
  "title": "Presentation title",
  "slides": [
    {
      "title": "Slide title",
      "bullets": ["First point", "Second point"],
      "notes": "Optional original source references and speaker notes"
    }
  ]
}
```

`title` and `slides` are required. Each slide requires a string title and an
array of string bullets. Notes may be absent, null or a string. Empty bullet
arrays create a title-only slide. Text is literal: there is no Markdown parser,
clinical interpretation, synthetic source content or inferred tool execution.

## Package and layout

- Standalone 16:9 deck: 12,192,000 × 6,858,000 EMU (13⅓ × 7½ inches).
- Embedded package parts include a theme, slide master, blank layout, slide
  relationships, core/app metadata and optional notes master/notes slides.
- Slide title, bullets and presentation footer are native editable text shapes.
  Each supplied bullet is one paragraph; embedded newlines become text breaks.
- Layout uses fixed positions and a deterministic font-size choice: 22pt for
  up to five bullets, 18pt for six to eight, 14pt for larger lists; titles are
  32pt. Normal autofit lets office applications wrap/shrink dense text.
- Chinese and other Unicode text is XML-escaped and UTF-8 encoded. Fonts are
  Aptos/Arial with Microsoft YaHei for East Asian text; fonts are not embedded
  and the viewer may substitute installed fonts.
- Optional speaker notes preserve the caller's full text, including source URLs
  and missing-data explanations. Source notes are not converted into guessed
  citations, images or fetched content.

The creator never truncates or automatically splits the supplied content.
Callers should split dense material into readable slides. This first creator
does not generate images, tables, charts, diagrams, animations or a copied
external template. Existing PPTX reading and conservative editing remain
separate APIs.

## Limits and errors

Supports 1–100 slides, at most 100 bullet paragraphs per slide, and 2,000,000
UTF-16 text units across the presentation title, slide titles, bullets and
notes. Invalid XML 1.0 controls/noncharacters or unpaired surrogate units are
rejected through `PptxError::InvalidPresentation`. OPC/ZIP failures are reported
through the same creation error. No external relationships are introduced.

## Preview CLI

`moonleaf-preview create-pptx OUTPUT` reads the input JSON from stdin and writes
a new PPTX through the existing exclusive-create file adapter. The shared
dispatcher works in the native and JavaScript preview targets. For the compiled
JavaScript executable, invoke `node moonleaf-preview.cjs create-pptx OUTPUT`.

The CLI accepts up to 4,194,304 UTF-16 units of JSON and prints a small receipt:
`{contract:"moonleaf.pptx-create.v1",slides,bytes}`. It does not call a model,
fetch source content or render the generated deck.

This feature was compiled and formatted with generated interfaces. No created
deck demo, rendering pass, test suite, model call or network access was used in
this implementation task.
