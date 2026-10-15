///|
fn[T, U] Option::and_then(self : T?, f : (T) -> U?) -> U? {
  match self {
    None => None
    Some(value) => f(value)
  }
}

///|
priv struct TableLayout {
  x : Int?
  y_offset : Int
  border : Int
  top : Int
  bottom : Int
  left : Int
  right : Int
}

///|
fn integer(e : @xml.Element?, attr : String, fallback : Int) -> Int raise {
  match e.and_then(e => e.attribute(attr)) {
    None => fallback
    Some(s) => @string.parse_int(s)
  }
}

///|
fn property_on(e : @xml.Element) -> Bool {
  !(e.attribute("val") == Some("0") ||
  e.attribute("val") == Some("false") ||
  e.attribute("val") == Some("off"))
}

///|
/// Never silently flatten unsupported semantic content into a successful receipt.
fn validate_profile(document_package : @opc.Package) -> Unit raise {
  fn walk(e : @xml.Element) -> Unit raise PdfError {
    let name = e.local_name()
    guard [
      "document", "body", "p", "pPr", "r", "rPr", "t", "br", "sectPr", "pgSz", "pgMar",
      "jc", "spacing", "ind", "rFonts", "sz", "szCs", "lang", "u", "b", "i", "color",
      "tbl", "tblPr", "tblW", "tblGrid", "gridCol", "tr", "trPr", "trHeight", "tc",
      "tcPr", "tcW", "gridSpan", "proofErr", "bookmarkStart", "bookmarkEnd", "pStyle",
      "rStyle", "numPr", "numId", "ilvl", "cols", "docGrid", "keepLines", "keepNext",
      "pageBreakBefore", "widowControl", "bidi", "snapToGrid", "kern", "autoSpaceDE",
      "autoSpaceDN", "kinsoku", "overflowPunct", "wordWrap", "adjustRightInd", "topLinePunct",
      "suppressLineNumbers", "textAlignment", "tblpPr", "tblStyle", "tblInd", "tblOverlap",
      "tblLayout", "tblCellMar", "tcMar", "tblBorders", "top", "bottom", "left",
      "right", "insideH", "insideV", "vAlign",
    ].contains(name) else {
      raise Unsupported("OOXML element outside legal-v1 profile: " + name)
    }
    if name == "br" {
      guard e.attribute("type") is None ||
        e.attribute("type") == Some("page") ||
        e.attribute("type") == Some("textWrapping") else {
        raise Unsupported("column break")
      }
    }
    if name == "u" {
      guard e.attribute("val") is None || e.attribute("val") == Some("single") else {
        raise Unsupported("underline style")
      }
    }
    if name == "bidi" && property_on(e) {
      raise Unsupported("RTL layout")
    }
    if name == "keepNext" && property_on(e) {
      raise Unsupported("keep-with-next group")
    }
    if name == "pageBreakBefore" && property_on(e) {
      raise Unsupported("pageBreakBefore; use explicit page break")
    }
    if name == "cols" && e.attribute("num") is Some(n) && n != "1" {
      raise Unsupported("multi-column section")
    }
    if name == "tblLayout" && e.attribute("type") != Some("fixed") {
      raise Unsupported("automatic table layout")
    }
    for child in e.child_elements() {
      walk(child)
    }
  }
  walk(@xml.parse(document_package.text("word/document.xml")))
}

///|
fn chinese_number(n : Int) -> String raise PdfError {
  let digits = [
    "零", "一", "二", "三", "四", "五", "六", "七", "八", "九",
  ]
  guard n > 0 && n < 100 else {
    raise Unsupported("Chinese list counter outside 1..99")
  }
  if n < 10 {
    digits[n]
  } else {
    (if n / 10 == 1 { "" } else { digits[n / 10] }) +
    "十" +
    (if n % 10 == 0 { "" } else { digits[n % 10] })
  }
}

///|
/// Resolve bounded single-level decimal/Chinese labels before rich-flow inspection.
fn numbered_document(document_package : @opc.Package) -> @opc.Package raise {
  if !document_package.has_part("word/numbering.xml") {
    return document_package
  }
  let numbering = @xml.parse(document_package.text("word/numbering.xml"))
  let counters : Map[String, Int] = Map([])
  let formats : Map[String, (String, String, Int)] = Map([])
  for num in numbering.children_named("num") {
    let id = num.attribute("numId").unwrap_or("")
    let abstract_id = num
      .first_child("abstractNumId")
      .and_then(e => e.attribute("val"))
      .unwrap_or("")
    guard num.first_child("lvlOverride") is None else {
      raise Unsupported("numbering override")
    }
    for definition in numbering.children_named("abstractNum") {
      if definition.attribute("abstractNumId") == Some(abstract_id) {
        for level in definition.children_named("lvl") {
          let ilvl = level.attribute("ilvl").unwrap_or("0")
          let fmt = level
            .first_child("numFmt")
            .and_then(e => e.attribute("val"))
            .unwrap_or("decimal")
          let text = level
            .first_child("lvlText")
            .and_then(e => e.attribute("val"))
            .unwrap_or("%1.")
          let start = integer(level.first_child("start"), "val", 1)
          formats[id + ":" + ilvl] = (fmt, text, start)
        }
      }
    }
  }
  fn rewrite(
    e : @xml.Element,
    formats : Map[String, (String, String, Int)],
    counters : Map[String, Int],
  ) -> @xml.Element raise {
    let children = e.children.map(node => {
      match node {
        Element(child) => @xml.Element(rewrite(child, formats, counters))
        _ => node
      }
    })
    let e = { ..e, children, }
    if e.local_name() != "p" {
      return e
    }
    let np = e.first_child("pPr").and_then(e => e.first_child("numPr"))
    let id = np
      .and_then(e => e.first_child("numId"))
      .and_then(e => e.attribute("val"))
      .unwrap_or("0")
    if id == "0" {
      return e
    }
    let level = np
      .and_then(e => e.first_child("ilvl"))
      .and_then(e => e.attribute("val"))
      .unwrap_or("0")
    guard level == "0" else { raise Unsupported("multi-level list") }
    guard formats.get(id + ":" + level) is Some((fmt, pattern, start)) else {
      raise Unsupported("missing numbering definition")
    }
    let n = counters.get(id).unwrap_or(start)
    counters[id] = n + 1
    let number = match fmt {
      "decimal" => n.to_string()
      "chineseCounting" => chinese_number(n)
      _ => raise Unsupported("numbering format: " + fmt)
    }
    let prefix = pattern.replace(old="%1", new=number)
    guard !prefix.contains("%") else {
      raise Unsupported("multi-level number placeholder")
    }
    let properties = e.first_child("r").and_then(r => r.first_child("rPr"))
    let run_children : Array[@xml.Node] = []
    if properties is Some(p) {
      run_children.push(Element(p))
    }
    run_children.push(
      Element({ name: "w:t", attributes: [], children: [Text(prefix)], }),
    )
    let run : @xml.Node = Element({
      name: "w:r",
      attributes: [],
      children: run_children,
    })
    let result : Array[@xml.Node] = []
    let mut inserted = false
    for child in e.children {
      if !inserted && child is Element(c) && c.local_name() == "r" {
        result.push(run)
        inserted = true
      }
      result.push(child)
    }
    guard inserted else {
      raise Unsupported("numbered paragraph without text run")
    }
    { ..e, children: result, }
  }
  let rewritten = rewrite(
    @xml.parse(document_package.text("word/document.xml")),
    formats,
    counters,
  )
  document_package.replace_text("word/document.xml", @xml.serialize(rewritten))
}

///|
fn table_layouts(document_package : @opc.Package) -> Array[TableLayout] raise {
  let root = @xml.parse(document_package.text("word/document.xml"))
  guard root.first_child("body") is Some(body) else {
    raise Unsupported("missing document body")
  }
  let layouts : Array[TableLayout] = []
  for table in body.children_named("tbl") {
    let pr = table.first_child("tblPr")
    let floating = pr.and_then(e => e.first_child("tblpPr"))
    if floating is Some(f) {
      guard f.attribute("horzAnchor") == Some("page") &&
        f.attribute("vertAnchor") == Some("text") &&
        f.attribute("tblpXSpec") is None &&
        f.attribute("tblpYSpec") is None else {
        raise Unsupported("floating table anchor")
      }
    }
    let margins = pr.and_then(e => e.first_child("tblCellMar"))
    let borders = pr.and_then(e => e.first_child("tblBorders"))
    let mut border = 0
    if borders is Some(bs) {
      for edge in bs.child_elements() {
        guard edge.attribute("val") == Some("single") &&
          (
            edge.attribute("color") is None ||
            edge.attribute("color") == Some("auto") ||
            edge.attribute("color") == Some("000000")
          ) else {
          raise Unsupported("table border style")
        }
        let size = integer(Some(edge), "sz", 4) * 20 / 8
        if border != 0 && border != size {
          raise Unsupported("mixed table border widths")
        }
        border = size
      }
    }
    layouts.push({
      x: floating.map(f => integer(Some(f), "tblpX", 0)),
      y_offset: integer(floating, "tblpY", 0),
      border,
      top: integer(margins.and_then(e => e.first_child("top")), "w", 0),
      bottom: integer(margins.and_then(e => e.first_child("bottom")), "w", 0),
      left: integer(margins.and_then(e => e.first_child("left")), "w", 108),
      right: integer(margins.and_then(e => e.first_child("right")), "w", 108),
    })
  }
  layouts
}
