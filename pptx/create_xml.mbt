///|
priv struct CreatedSlide {
  title : String
  bullets : Array[String]
  notes : String?
}

///|
fn created_pptx_text(text : String) -> String raise PptxError {
  for i = 0; i < text.length(); {
    let unit = text.code_unit_at(i).to_int()
    if unit >= 0xD800 && unit <= 0xDBFF {
      if i + 1 >= text.length() {
        raise InvalidPresentation(
          message="PPTX text contains an unpaired UTF-16 surrogate",
        )
      }
      let next = text.code_unit_at(i + 1).to_int()
      if next < 0xDC00 || next > 0xDFFF {
        raise InvalidPresentation(
          message="PPTX text contains an unpaired UTF-16 surrogate",
        )
      }
      continue i + 2
    }
    if (unit < 0x20 && unit != 9 && unit != 10 && unit != 13) ||
      (unit >= 0xDC00 && unit <= 0xDFFF) ||
      unit > 0xFFFD {
      raise InvalidPresentation(
        message="PPTX text contains a character forbidden by XML 1.0",
      )
    }
    continue i + 1
  }
  @xml.escape_text(text).replace_all(old="\r", new="&#13;")
}

///|
fn created_pptx_part(name : String, content : String) -> @opc.Part {
  { name, content: @utf8.encode(content).to_fixedarray(), }
}

///|
fn created_pptx_group() -> String {
  "<p:nvGrpSpPr><p:cNvPr id=\"1\" name=\"\"/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr><a:xfrm><a:off x=\"0\" y=\"0\"/><a:ext cx=\"0\" cy=\"0\"/><a:chOff x=\"0\" y=\"0\"/><a:chExt cx=\"0\" cy=\"0\"/></a:xfrm></p:grpSpPr>"
}

///|
fn created_pptx_run(
  text : String,
  size : Int32,
  bold : Bool,
  color : String,
) -> String raise PptxError {
  let out = StringBuilder()
  let lines = text
    .replace_all(old="\r\n", new="\n")
    .replace_all(old="\r", new="\n")
    .split("\n")
  for i, line in lines {
    if i > 0 {
      out <+ "<a:br/>"
    }
    out <+
      "<a:r><a:rPr lang=\"zh-CN\" sz=\"\{size}\" b=\"\{if bold { "1" } else { "0" }}\" dirty=\"0\"><a:solidFill><a:srgbClr val=\"\{color}\"/></a:solidFill><a:latin typeface=\"Aptos\"/><a:ea typeface=\"Microsoft YaHei\"/><a:cs typeface=\"Arial\"/></a:rPr><a:t xml:space=\"preserve\">\{created_pptx_text(line.to_owned())}</a:t></a:r>"
  }
  out.to_string()
}

///|
fn created_pptx_paragraph(
  text : String,
  size : Int32,
  bullet : Bool,
  bold : Bool,
  color : String,
) -> String raise PptxError {
  let properties = if bullet {
    "<a:pPr marL=\"285750\" indent=\"-228600\" lvl=\"0\"><a:lnSpc><a:spcPct val=\"110000\"/></a:lnSpc><a:spcAft><a:spcPts val=\"800\"/></a:spcAft><a:buFont typeface=\"Arial\"/><a:buChar char=\"•\"/></a:pPr>"
  } else {
    "<a:pPr><a:buNone/></a:pPr>"
  }
  "<a:p>\{properties}\{created_pptx_run(text, size, bold, color)}<a:endParaRPr lang=\"zh-CN\" sz=\"\{size}\"/></a:p>"
}

///|
fn created_pptx_shape(
  id : Int32,
  name : String,
  x : Int32,
  y : Int32,
  width : Int32,
  height : Int32,
  paragraphs : String,
  placeholder~ : String = "",
) -> String {
  "<p:sp><p:nvSpPr><p:cNvPr id=\"\{id}\" name=\"\{name}\"/><p:cNvSpPr txBox=\"1\"/><p:nvPr>\{placeholder}</p:nvPr></p:nvSpPr><p:spPr><a:xfrm><a:off x=\"\{x}\" y=\"\{y}\"/><a:ext cx=\"\{width}\" cy=\"\{height}\"/></a:xfrm><a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom><a:noFill/><a:ln><a:noFill/></a:ln></p:spPr><p:txBody><a:bodyPr wrap=\"square\" lIns=\"0\" tIns=\"0\" rIns=\"0\" bIns=\"0\" anchor=\"t\"><a:normAutofit/></a:bodyPr><a:lstStyle/>\{paragraphs}</p:txBody></p:sp>"
}

///|
fn created_pptx_slide(
  slide : CreatedSlide,
  deck_title : String,
  ordinal : Int32,
) -> String raise PptxError {
  let body = StringBuilder()
  let size = if slide.bullets.length() <= 5 {
    2200
  } else if slide.bullets.length() <= 8 {
    1800
  } else {
    1400
  }
  for bullet in slide.bullets {
    body.write_string(
      created_pptx_paragraph(bullet, size, true, false, "263445"),
    )
  }
  if slide.bullets.is_empty() {
    body <+ "<a:p><a:endParaRPr lang=\"zh-CN\" sz=\"2200\"/></a:p>"
  }
  let title = created_pptx_shape(
    2,
    "Slide title",
    685800,
    457200,
    10820400,
    914400,
    created_pptx_paragraph(slide.title, 3200, false, true, "152536"),
  )
  let content = created_pptx_shape(
    3,
    "Editable bullets",
    685800,
    1600200,
    10820400,
    4389120,
    body.to_string(),
  )
  let footer = created_pptx_shape(
    4,
    "Presentation footer",
    685800,
    6309360,
    10820400,
    274320,
    created_pptx_paragraph(
      deck_title + "  ·  " + ordinal.to_string(),
      1000,
      false,
      false,
      "657489",
    ),
  )
  "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><p:sld xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\" xmlns:p=\"http://schemas.openxmlformats.org/presentationml/2006/main\"><p:cSld><p:spTree>\{created_pptx_group()}\{title}\{content}\{footer}</p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sld>"
}

///|
fn created_pptx_notes(text : String) -> String raise PptxError {
  let paragraphs = StringBuilder()
  for
    line in text
    .replace_all(old="\r\n", new="\n")
    .replace_all(old="\r", new="\n")
    .split("\n") {
    paragraphs.write_string(
      created_pptx_paragraph(line.to_owned(), 1200, false, false, "263445"),
    )
  }
  let image = "<p:sp><p:nvSpPr><p:cNvPr id=\"2\" name=\"Slide image\"/><p:cNvSpPr><a:spLocks noGrp=\"1\" noRot=\"1\" noChangeAspect=\"1\"/></p:cNvSpPr><p:nvPr><p:ph type=\"sldImg\"/></p:nvPr></p:nvSpPr><p:spPr><a:xfrm><a:off x=\"685800\" y=\"457200\"/><a:ext cx=\"5486400\" cy=\"3086100\"/></a:xfrm><a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom></p:spPr></p:sp>"
  let notes = created_pptx_shape(
    3,
    "Speaker notes",
    685800,
    3886200,
    5486400,
    4800600,
    paragraphs.to_string(),
    placeholder="<p:ph type=\"body\" idx=\"1\"/>",
  )
  "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><p:notes xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\" xmlns:p=\"http://schemas.openxmlformats.org/presentationml/2006/main\"><p:cSld><p:spTree>\{created_pptx_group()}\{image}\{notes}</p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:notes>"
}

///|
fn created_pptx_relationship(
  id : String,
  kind : String,
  target : String,
) -> String {
  "<Relationship Id=\"\{id}\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/\{kind}\" Target=\"\{target}\"/>"
}

///|
fn created_pptx_relationships(body : String) -> String {
  "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">\{body}</Relationships>"
}
