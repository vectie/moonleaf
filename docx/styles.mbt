///|
/// DOCX-local style cascade, parsed from word/styles.xml.
priv struct DocxStyle {
  based_on : String?
  properties : ResolvedStyle
}

///|
priv struct StyleTable {
  mut default_paragraph_style_id : String?
  mut paragraph_default : ResolvedStyle
  mut run_default : ResolvedStyle
  paragraph_styles : Map[String, DocxStyle]
  character_styles : Map[String, DocxStyle]
}

///|
fn empty_paragraph_metadata() -> ParagraphMetadata {
  {
    alignment: None,
    spacing_before_twips: None,
    spacing_after_twips: None,
    line_twips: None,
    left_indent_twips: None,
    right_indent_twips: None,
    first_line_twips: None,
    hanging_twips: None,
  }
}

///|
fn empty_resolved_style() -> ResolvedStyle {
  {
    outline_level: None,
    paragraph: empty_paragraph_metadata(),
    font_ascii: None,
    font_east_asia: None,
    font_complex_script: None,
    color: None,
    highlight: None,
    strike: None,
  }
}

///|
fn[T] prefer(direct : T?, inherited : T?) -> T? {
  match direct {
    Some(value) => Some(value)
    None => inherited
  }
}

///|
fn merge_paragraph_style(
  base : ParagraphMetadata,
  direct : ParagraphMetadata,
) -> ParagraphMetadata {
  {
    alignment: prefer(direct.alignment, base.alignment),
    spacing_before_twips: prefer(
      direct.spacing_before_twips,
      base.spacing_before_twips,
    ),
    spacing_after_twips: prefer(
      direct.spacing_after_twips,
      base.spacing_after_twips,
    ),
    line_twips: prefer(direct.line_twips, base.line_twips),
    left_indent_twips: prefer(direct.left_indent_twips, base.left_indent_twips),
    right_indent_twips: prefer(
      direct.right_indent_twips,
      base.right_indent_twips,
    ),
    first_line_twips: prefer(direct.first_line_twips, base.first_line_twips),
    hanging_twips: prefer(direct.hanging_twips, base.hanging_twips),
  }
}

///|
fn merge_resolved_style(
  base : ResolvedStyle,
  direct : ResolvedStyle,
) -> ResolvedStyle {
  {
    outline_level: prefer(direct.outline_level, base.outline_level),
    paragraph: merge_paragraph_style(base.paragraph, direct.paragraph),
    font_ascii: prefer(direct.font_ascii, base.font_ascii),
    font_east_asia: prefer(direct.font_east_asia, base.font_east_asia),
    font_complex_script: prefer(
      direct.font_complex_script,
      base.font_complex_script,
    ),
    color: prefer(direct.color, base.color),
    highlight: prefer(direct.highlight, base.highlight),
    strike: prefer(direct.strike, base.strike),
  }
}

///|
fn run_style_from_pr(pr : @xml.Element?) -> ResolvedStyle {
  let result = empty_resolved_style()
  match pr {
    None => result
    Some(pr) => {
      let fonts = pr.first_child("rFonts")
      {
        ..result,
        font_ascii: string_attr(fonts, "ascii"),
        font_east_asia: string_attr(fonts, "eastAsia"),
        font_complex_script: string_attr(fonts, "cs"),
        color: string_attr(pr.first_child("color"), "val"),
        highlight: string_attr(pr.first_child("highlight"), "val"),
        strike: match pr.first_child("strike") {
          None => None
          Some(_) => Some(property_enabled(pr, "strike"))
        },
      }
    }
  }
}

///|
fn style_properties(element : @xml.Element) -> ResolvedStyle {
  let paragraph_pr = if element.local_name() == "pPr" {
    Some(element)
  } else {
    element.first_child("pPr")
  }
  let run_pr = if element.local_name() == "rPr" {
    Some(element)
  } else {
    element.first_child("rPr")
  }
  let result = run_style_from_pr(run_pr)
  match paragraph_pr {
    None => result
    Some(pr) =>
      {
        ..result,
        outline_level: int_attr(pr.first_child("outlineLvl"), "val"),
        paragraph: paragraph_metadata_from_pr(pr),
      }
  }
}

///|
fn empty_style_table() -> StyleTable {
  {
    default_paragraph_style_id: None,
    paragraph_default: empty_resolved_style(),
    run_default: empty_resolved_style(),
    paragraph_styles: {},
    character_styles: {},
  }
}

///|
fn parse_style_table(document_package : @opc.Package) -> StyleTable {
  if !document_package.has_part("word/styles.xml") {
    return empty_style_table()
  }
  let source = document_package.text("word/styles.xml") catch {
    _ => return empty_style_table()
  }
  let root = @xml.parse(source) catch { _ => return empty_style_table() }
  let table = empty_style_table()
  match root.first_child("docDefaults") {
    None => ()
    Some(defaults) => {
      match defaults.first_child("pPrDefault") {
        Some(x) => table.paragraph_default = style_properties(x)
        None => ()
      }
      match defaults.first_child("rPrDefault") {
        Some(x) => table.run_default = style_properties(x)
        None => ()
      }
    }
  }
  for element in root.child_elements() {
    if element.local_name() == "style" {
      match element.attribute("styleId") {
        None => ()
        Some(id) => {
          let style = {
            based_on: string_attr(element.first_child("basedOn"), "val"),
            properties: style_properties(element),
          }
          match element.attribute("type") {
            Some("character") => table.character_styles[id] = style
            Some("paragraph") => {
              table.paragraph_styles[id] = style
              match element.attribute("default") {
                Some("1") | Some("true") =>
                  table.default_paragraph_style_id = Some(id)
                _ => ()
              }
            }
            _ => ()
          }
        }
      }
    }
  }
  table
}

///|
fn add_style_warning(
  warnings : Array[@scene.Warning],
  code : String,
  id : String,
) -> Unit {
  warnings.push({
    code,
    message: "DOCX style reference: " + id,
    part: Some("word/styles.xml"),
  })
}

///|
fn resolve_style(
  styles : Map[String, DocxStyle],
  id : String,
  defaults : ResolvedStyle,
  warnings : Array[@scene.Warning],
) -> ResolvedStyle {
  let visiting : Map[String, Bool] = {}
  fn walk(id : String) -> ResolvedStyle {
    if visiting.contains(id) {
      add_style_warning(warnings, "DOCX_STYLE_CYCLE", id)
      return defaults
    }
    match styles.get(id) {
      None => {
        add_style_warning(warnings, "DOCX_STYLE_MISSING", id)
        defaults
      }
      Some(style) => {
        visiting[id] = true
        let base = match style.based_on {
          None => defaults
          Some(parent) =>
            match styles.get(parent) {
              None => {
                add_style_warning(warnings, "DOCX_STYLE_PARENT_MISSING", parent)
                defaults
              }
              Some(_) => walk(parent)
            }
        }
        visiting.remove(id)
        merge_resolved_style(base, style.properties)
      }
    }
  }
  walk(id)
}
