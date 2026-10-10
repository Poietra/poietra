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
test "a baked polyline path draws its own points, fills like a shape and bounds them" {
  let state = {
    ..@scene.default_state(Path),
    x: 50.0,
    y: 20.0,
    width: 400.0,
    height: -180.0,
    strokeWidth: 0.0,
    points: Some([
      { x: -4.0, y: 6.0, },
      { x: 10.0, y: -2.0, },
      { x: 3.0, y: 9.0, },
    ]),
  }
  let item : Drawable = {
    id: "graph",
    kind: Path,
    state,
    world: None,
    clips: None,
    progress: 1.0,
    order: Together,
    image: None,
    video_frame: None,
  }
  let resources : Resources = {
    equation: fn(_) { None },
    measure_text: fn(_, _) {
      { width: 0.0, height: 0.0, line_height: 0.0, baseline: 0.0, }
    },
    image: fn(_) { None },
    font_styles: fn(_) { "" },
  }
  assert_true(shape_geometry(Path, state) == Some(Path("M-4 6L10 -2L3 9")))
  // Width, height and the cubic control points no longer describe the shape.
  assert_true(
    shape_geometry(Path, { ..state, width: 1.0, height: 1.0, }) ==
    shape_geometry(Path, state),
  )
  assert_true(shape_geometry(Path, { ..state, points: Some([]), }) is None)
  assert_true(
    shape_geometry(Path, { ..state, points: Some([{ x: 1.0, y: 2.0, }]), })
    is None,
  )
  let frame : RenderFrame = {
    width: 640.0,
    height: 360.0,
    background: "#000000",
    objects: [item],
  }
  let filled = frame_to_svg(frame, "t", false, resources)
  assert_true(filled.contains("d=\"M-4 6L10 -2L3 9\" fill-opacity=\"1\""))
  assert_true(filled.contains("fill=\"#d7d8e4\""))
  let unfilled = frame_to_svg(
    { ..frame, objects: [{ ..item, state: { ..state, fill: "none", }, }], },
    "t",
    false,
    resources,
  )
  assert_true(unfilled.contains("fill=\"none\""))
  // Every state carries a fill colour, so a legacy single-bezier path must keep
  // its stroke-only rendering instead of painting its implicit closure.
  let legacy = { ..state, points: None, }
  let legacy_svg = frame_to_svg(
    { ..frame, objects: [{ ..item, state: legacy, }], },
    "t",
    false,
    resources,
  )
  assert_true(
    legacy_svg.contains("d=\"M0 0 C140 0 260 -180 400 -180\" fill=\"none\""),
  )
  let bounds = object_bounds(item, resources)
  assert_eq((bounds.x, bounds.y), (46.0, 18.0))
  assert_eq((bounds.width, bounds.height), (14.0, 11.0))
}
