///|
fn pptx_cell(value : String) -> String {
  "<a:tc><a:txBody><a:bodyPr/><a:lstStyle/><a:p><a:r><a:t>" +
  @xml.escape_text(value) +
  "</a:t></a:r></a:p></a:txBody><a:tcPr/></a:tc>"
}

///|
fn pptx_rows(values : Array[Array[String]]) -> String {
  "<a:tbl><a:tblPr/><a:tblGrid>" +
  Array::make(values[0].length(), "<a:gridCol w=\"100\"/>").join("") +
  "</a:tblGrid>" +
  values.map(row => "<a:tr>" + row.map(pptx_cell).join("") + "</a:tr>").join("") +
  "</a:tbl>"
}

///|
fn pptx_frame(table : String) -> String {
  "<p:graphicFrame><p:nvGraphicFramePr><p:cNvPr id=\"42\"/></p:nvGraphicFramePr><a:graphic><a:graphicData uri=\"http://schemas.openxmlformats.org/drawingml/2006/table\">" +
  table +
  "</a:graphicData></a:graphic></p:graphicFrame>"
}

///|
fn pptx_source(content : String) -> @opc.Package {
  let source : @opc.Package = { parts: [], }
  source
  .replace_text(
    "ppt/presentation.xml", "<p:presentation xmlns:p=\"http://schemas.openxmlformats.org/presentationml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\"><p:sldIdLst><p:sldId r:id=\"second\"/><p:sldId r:id=\"first\"/></p:sldIdLst></p:presentation>",
  )
  .replace_text(
    "ppt/_rels/presentation.xml.rels", "<Relationships><Relationship Id=\"first\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide\" Target=\"slides/slide1.xml\"/><Relationship Id=\"second\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide\" Target=\"slides/slide9.xml\"/></Relationships>",
  )
  .replace_text(
    "ppt/slides/slide1.xml", "<p:sld xmlns:p=\"http://schemas.openxmlformats.org/presentationml/2006/main\" xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\"><p:cSld><p:spTree/></p:cSld></p:sld>",
  )
  .replace_text(
    "ppt/slides/slide9.xml",
    "<p:sld xmlns:p=\"http://schemas.openxmlformats.org/presentationml/2006/main\" xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\" show=\"0\"><p:cSld><p:spTree>" +
    content +
    "</p:spTree></p:cSld></p:sld>",
  )
}

///|
fn pptx_import(
  content : String,
  header~ : @jsontable.PptxHeader = FirstSlideTableRow,
) -> @jsontable.PptxTable raise {
  @jsontable.extract_pptx(
    pptx_source(content),
    table_id="slide:1/table:1",
    header~,
  )
}

///|
test "pptx table discovery respects actual slide and nested group order with immutable text data" {
  let frame = pptx_frame(
    pptx_rows([
      ["id", "amount", "note"],
      ["001", "12.50", "=1+1"],
      ["002", "", "雪😀 & <tag>,\"x\""],
    ]),
  )
  let source = pptx_source("<p:grpSp>" + frame + "</p:grpSp>" + frame)
  let before = source.parts.copy()
  let tables = @pptx.read_tables(source)
  assert_eq(tables.length(), 2)
  assert_eq(tables[0].id, "slide:1/table:1")
  assert_eq(tables[1].id, "slide:1/table:2")
  assert_eq(tables[0].part, "ppt/slides/slide9.xml")
  assert_true(tables[0].hidden_slide)
  assert_eq(tables[0].shape_id, "42")
  let imported = @jsontable.extract_pptx(
    source,
    table_id=tables[0].id,
    header=FirstSlideTableRow,
  )
  assert_eq(imported.source_rows, [2, 3])
  assert_eq(imported.table.text_rows(), [
    ["001", "12.50", "=1+1"],
    ["002", "", "雪😀 & <tag>,\"x\""],
  ])
  imported.table.rows[0][0] = Text("changed")
  tables[0].rows[0][0] = "changed"
  assert_eq(source.parts, before)
  assert_eq(@pptx.read_tables(source)[0].rows[0][0], "id")
}

///|
test "pptx rich runs explicit breaks and blank paragraphs retain source text" {
  let table = pptx_rows([["text"]]).replace_all(
    old="<a:p><a:r><a:t>text</a:t></a:r></a:p>",
    new="<a:p><a:pPr/><a:r><a:rPr b=\"1\"/><a:t> A</a:t></a:r><a:r><a:t>B </a:t></a:r><a:br/><a:r><a:t>C&#9;D</a:t></a:r><a:endParaRPr/></a:p><a:p/><a:p><a:r><a:t>E</a:t></a:r></a:p>",
  )
  let imported = pptx_import(
    pptx_frame(table),
    header=SlideTableColumns(["text"]),
  )
  assert_eq(imported.table.text_rows(), [[" AB \nC\tD\n\nE"]])
  assert_eq(imported.source_rows, [1])
}

///|
test "pptx query and literal xlsx export retain original physical row references" {
  let imported = pptx_import(
    pptx_frame(
      pptx_rows([
        ["id", "cost", "note"],
        ["b", "12.5", "=1+1"],
        ["a", "25", "雪😀"],
        ["c", "9", ""],
      ]),
    ),
  )
  let recipe = @jsontable.parse_query_recipe(
    "{\"version\":1,\"filters\":[{\"column\":\"cost\",\"mode\":\"number\",\"op\":\"ge\",\"value\":10}],\"sort\":[{\"column\":\"cost\",\"mode\":\"number\",\"direction\":\"desc\",\"blanks\":\"last\"}],\"select\":[\"id\",\"note\"],\"limit\":10}",
  )
  let result = imported.table.query(recipe)
  assert_eq(result.source_rows.map(i => imported.source_rows[i - 1]), [3, 2])
  let reopened = @jsontable.extract_xlsx(
    @opc.open(result.table.export_xlsx()),
    sheet_name="JSON data",
    range="A1:B3",
    header=FirstRow,
  )
  assert_eq(reopened.table, result.table)
  assert_eq(result.table.text_rows(), [["a", "雪😀"], ["b", "=1+1"]])
}

///|
test "pptx unsupported table does not block an ordinary one and no notes are read" {
  let good = pptx_frame(pptx_rows([["id"], ["001"]]))
  let merged = good.replace_all(old="<a:tc>", new="<a:tc gridSpan=\"2\">")
  let source = pptx_source(merged + good).replace_text(
    "ppt/slides/_rels/slide9.xml.rels", "<invalid notes relationship",
  )
  let tables = @pptx.read_tables(source)
  assert_true(tables[0].refusal is Some(_))
  assert_eq(tables[0].rows, [])
  assert_eq(tables[1].refusal, None)
  assert_eq(
    @jsontable.extract_pptx(
      source,
      table_id="slide:1/table:2",
      header=FirstSlideTableRow,
    ).table.text_rows(),
    [["001"]],
  )
  assert_true(
    try
      @jsontable.extract_pptx(
        source,
        table_id="slide:1/table:1",
        header=FirstSlideTableRow,
      )
    catch {
      _ => true
    } noraise {
      _ => false
    },
  )
}

///|
test "pptx selected merges fields hyperlinks unknown content and malformed grids refuse" {
  let frame = pptx_frame(pptx_rows([["id"], ["001"]]))
  for
    altered in [
      frame.replace_all(old="<a:tc>", new="<a:tc rowSpan=\"1\">"),
      frame.replace_all(old="<a:tc>", new="<a:tc hMerge=\"false\">"),
      frame
      .replace_all(old="<a:r>", new="<a:fld>")
      .replace_all(old="</a:r>", new="</a:fld>"),
      frame.replace_all(old="<a:r>", new="<a:r><a:rPr><a:hlinkClick/></a:rPr>"),
      frame.replace_all(old="<a:tcPr/>", new="<a:tcPr><a:extLst/></a:tcPr>"),
      frame.replace_all(old="<a:t>001</a:t>", new="<a:t><a:r/></a:t>"),
      frame.replace_all(old="<a:txBody>", new="<a:txBody><unsupported/>"),
      frame.replace_all(
        old="<a:gridCol w=\"100\"/>",
        new="<a:gridCol/><a:gridCol/>",
      ),
      frame.replace_all(old="</a:tblGrid>", new="</a:tblGrid><a:tblGrid/>"),
      frame.replace_all(
        old="<a:t>001</a:t>",
        new="<a:t>001</a:t><a:t>002</a:t>",
      ),
    ] {
    assert_true(
      try pptx_import(altered) catch {
        _ => true
      } noraise {
        _ => false
      },
    )
  }
}

///|
test "pptx exact headers support header-only data and refuse ambiguous selections" {
  let frame = pptx_frame(pptx_rows([["id", "name"]]))
  let empty = pptx_import(frame)
  assert_eq(empty.table.rows, [])
  let names = ["a", "b"]
  let all = pptx_import(frame, header=SlideTableColumns(names))
  names[0] = "changed"
  assert_eq(all.table.columns, ["a", "b"])
  assert_eq(all.source_rows, [1])
  for
    header in [
      @jsontable.SlideTableColumns(["a"]),
      SlideTableColumns(["a", "a"]),
      SlideTableColumns(["", "b"]),
    ] {
    assert_true(
      try pptx_import(frame, header~) catch {
        _ => true
      } noraise {
        _ => false
      },
    )
  }
  assert_true(
    try
      @jsontable.extract_pptx(
        pptx_source(frame),
        table_id="slide:01/table:1",
        header=FirstSlideTableRow,
      )
    catch {
      _ => true
    } noraise {
      _ => false
    },
  )
}

///|
test "pptx namespace changes and external slide relationships fail discovery" {
  let source = pptx_source(pptx_frame(pptx_rows([["id"]])))
  let slide = source.text("ppt/slides/slide9.xml")
  for
    altered in [
      slide.replace_all(old="xmlns:a=", new="xmlns:a=\"wrong\" unused="),
      slide.replace_all(old="<a:tbl>", new="<a:tbl xmlns:a=\"wrong\">"),
      slide.replace_all(old="</p:sld>", new=""),
    ] {
    assert_true(
      try
        @pptx.read_tables(source.replace_text("ppt/slides/slide9.xml", altered))
      catch {
        _ => true
      } noraise {
        _ => false
      },
    )
  }
  let rels = source.text("ppt/_rels/presentation.xml.rels")
  assert_true(
    try
      @pptx.read_tables(
        source.replace_text(
          "ppt/_rels/presentation.xml.rels",
          rels.replace_all(old="Target=", new="TargetMode=\"External\" Target="),
        ),
      )
    catch {
      _ => true
    } noraise {
      _ => false
    },
  )
  let empty = source.replace_text(
    "ppt/presentation.xml", "<p:presentation xmlns:p=\"http://schemas.openxmlformats.org/presentationml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\"/>",
  )
  assert_eq(@pptx.read_tables(empty), [])
}

///|
test "pptx bounded columns rows and imported header text" {
  assert_true(
    try pptx_import(pptx_frame(pptx_rows([Array::make(129, "x")]))) catch {
      _ => true
    } noraise {
      _ => false
    },
  )
  assert_true(
    try pptx_import(pptx_frame(pptx_rows(Array::make(1001, ["x"])))) catch {
      _ => true
    } noraise {
      _ => false
    },
  )
  assert_eq(
    pptx_import(pptx_frame(pptx_rows(Array::make(1000, ["x"])))).table.rows.length(),
    999,
  )
  assert_true(
    try
      pptx_import(
        pptx_frame(pptx_rows([["x"]])),
        header=SlideTableColumns(["x".repeat(2000001)]),
      )
    catch {
      _ => true
    } noraise {
      _ => false
    },
  )
}

///|
test "pptx table slide references use direct list and exact r:id rather than nested decoys" {
  let source = pptx_source(pptx_frame(pptx_rows([["id"], ["001"]])))
  let xml = source.text("ppt/presentation.xml")
  let altered = xml
    .replace_all(
      old="<p:sldIdLst>",
      new="<p:extLst><p:sldIdLst><p:sldId r:id=\"missing\"/></p:sldIdLst></p:extLst><p:sldIdLst>",
    )
    .replace_all(
      old="r:id=\"second\"",
      new="other:id=\"first\" xmlns:other=\"ignored\" r:id=\"second\"",
    )
  assert_eq(
    @pptx.read_tables(source.replace_text("ppt/presentation.xml", altered)),
    @pptx.read_tables(source),
  )
}

///|
test "pptx table discovery bounds aggregate cells across repeated slide references" {
  let source = pptx_source(pptx_frame(pptx_rows(Array::make(1000, [""]))))
  for count in [100, 101] {
    let ids = Array::make(count, "<p:sldId r:id=\"second\"/>").join("")
    let changed = source.replace_text(
      "ppt/presentation.xml",
      "<p:presentation xmlns:p=\"http://schemas.openxmlformats.org/presentationml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\"><p:sldIdLst>" +
      ids +
      "</p:sldIdLst></p:presentation>",
    )
    if count == 100 {
      assert_eq(@pptx.read_tables(changed).length(), 100)
    } else {
      assert_true(
        try @pptx.read_tables(changed) catch {
          _ => true
        } noraise {
          _ => false
        },
      )
    }
  }
}
