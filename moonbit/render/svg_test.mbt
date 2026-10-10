///|
test "XML escaping preserves spans, pairs and whitespace around replacements" {
  assert_eq(escape_xml(""), "")
  assert_eq(escape_xml("日本語😀\t\r\n"), "日本語😀\t\r\n")
  assert_eq(escape_xml("<&\"'>"), "&lt;&amp;&quot;&apos;&gt;")
  let broken = String::from_array([
    'A',
    (0xd800).unsafe_to_char(),
    'B',
    (0xdc00).unsafe_to_char(),
    'C',
  ])
  assert_eq(escape_xml(broken), "A�B�C")
  let removed = String::from_array([
    'A',
    (0).unsafe_to_char(),
    (0xb).unsafe_to_char(),
    (0xffff).unsafe_to_char(),
    'B',
  ])
  assert_eq(escape_xml(removed), "AB")
  assert_eq(
    escape_xml("😀<&日本語>😀"),
    "😀&lt;&amp;日本語&gt;😀",
  )
  let span = String::from_array(Array::make(10000, 'a')[:])
  assert_eq(escape_xml(span), span)
  assert_eq(escape_xml(span + "&" + span), span + "&amp;" + span)
}

///|
/// Real `mathjax-full` 3.2.2 markup for `\left|\sin(x^{2})\right|` with
/// `fontCache: "none"`: a stretched delimiter nests its own `<svg>` viewport.
test "a stretched delimiter keeps its nested viewport and glyph in the emitted SVG" {
  let bar = "M139 -249H137Q125 -249 119 -235V251L120 737Q130 750 139 750Q152 750 159 735V-235Q151 -249 141 -249H139Z"
  let viewport : MathNode = {
    tag: Viewport,
    attributes: [
      ("width", "278"),
      ("height", "1267.9"),
      ("y", "-383.9"),
      ("x", "27.5"),
      ("viewBox", "0 -157.1 278 1267.9"),
    ],
    children: [
      {
        tag: Path,
        attributes: [("d", bar), ("transform", "scale(1,1.904)")],
        children: [],
      },
    ],
  }
  let equation : Equation = {
    x: 0.0,
    y: -883.9,
    width: 3680.6,
    height: 1267.9,
    tree: {
      tag: Group,
      attributes: [],
      children: [{ tag: Group, attributes: [], children: [viewport], }],
    },
    glyphs: 1,
  }
  assert_eq(
    equation_markup(equation, 1.0, Together),
    "<g><g><svg width=\"278\" height=\"1267.9\" y=\"-383.9\" x=\"27.5\" viewBox=\"0 -157.1 278 1267.9\"><path d=\"\{bar}\" transform=\"scale(1,1.904)\"/></svg></g></g>",
  )

  // Canvas2D has no nested viewport: the same geometry as translate + scale.
  let (scale, x, y) = math_viewport(viewport).unwrap()
  assert_eq(number(scale), "1")
  assert_eq(number(x), "27.5")
  assert_eq(number(y), "-226.8")

  // `preserveAspectRatio="xMidYMid meet"` uses the smaller ratio and centres.
  let (meet, meet_x, meet_y) = math_viewport({
    tag: Viewport,
    attributes: [("width", "100"), ("height", "50"), ("viewBox", "2 3 10 10")],
    children: [],
  }).unwrap()
  assert_eq(number(meet), "5")
  assert_eq(number(meet_x), "15")
  assert_eq(number(meet_y), "-15")
  assert_true(math_view_box("0 -157.1 278") is None)
  assert_true(math_view_box("0 0 0 10") is None)
}
