///|
test "parse_page_yaml handles multiline quoted strings and clean_latex_math" {
  let yaml =
    #|pageType: content
    #|elements:
    #|- elementId: f
    #|  elementType: text
    #|  bounds:
    #|  - 75
    #|  - 145
    #|  - 410
    #|  - 145
    #|  content:
    #|    text: '\(P=D Q-\alpha D-\frac{\beta D^2}{Q}-\gamma\)
    #|
    #|      \(\frac{\partial P}{\partial D}=Q-\alpha-\frac{2\beta D}{Q}\)'
    #|    fontSize: 27
  let parsed = @pptx.parse_page_yaml(yaml)
  guard parsed is { "elements": Array(elements), .. } else {
    fail("expected elements array")
  }
  assert_eq(elements.length(), 1)
  let text = match elements[0] {
    { "content": { "text": String(t), .. }, .. } => @pptx.clean_latex_math(t)
    _ => ""
  }
  assert_eq(text, "P=DQ-α D-βD²/Q-γ\n∂P/∂D=Q-α-2βD/Q")
}

///|
test "parse_page_yaml parses nested - - table rows" {
  let yaml =
    #|elements:
    #|- elementId: table
    #|  elementType: table
    #|  bounds:
    #|  - 65
    #|  - 128
    #|  - 830
    #|  - 330
    #|  rows:
    #|  - - text: 假设
    #|      fontSize: 16
    #|    - text: 核心关系
    #|      fontSize: 16
    #|  - - text: H1a / H1b
    #|      fontSize: 16
    #|    - text: 倒U型关系
    #|      fontSize: 16
  let parsed = @pptx.parse_page_yaml(yaml)
  guard parsed is { "elements": Array(elements), .. } else {
    fail("expected elements")
  }
  assert_eq(elements.length(), 1)
  guard elements[0] is { "rows": Array(rows), .. } else {
    fail("expected rows array")
  }
  assert_eq(rows.length(), 2)
}
