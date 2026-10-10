///|
test "diagram Write uses per-element paths and escapes semantic labels without storing derived geometry" {
  let state = @scene.default_state(Geometry)
  let full = diagram_geometry(state, 1.0)
  assert_eq(full.curves.length(), 7)
  assert_true(!full.limited)
  assert_eq(diagram_geometry(state, 0.0).curves.length(), 0)
  assert_true(
    diagram_markup(full, state, 0.5).contains("stroke-dashoffset=\"0.5\""),
  )
  let points = state.geometry.unwrap().points.copy()
  points["a"] = { ..points["a"], label: "<script>&", }
  let edited = {
    ..state,
    geometry: Some({ ..state.geometry.unwrap(), points, }),
  }
  let markup = diagram_markup(diagram_geometry(edited, 1.0), edited, 1.0)
  assert_true(markup.contains("&lt;script&gt;&amp;"))
  assert_true(!markup.contains("NaN") && !markup.contains("Infinity"))
  assert_true(!edited.to_json().stringify().contains("curves"))
}
