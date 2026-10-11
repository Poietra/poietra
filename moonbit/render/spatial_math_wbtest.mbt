///|
test "network paths retain semantic identities, loops, parallel bends and escaped labels" {
  let state = @scene.default_state(Network)
  let definition = state.network.unwrap()
  let edges = definition.edges.copy()
  edges["loop"] = {
    ..edges["ab"],
    from: "a",
    to: "a",
    directed: true,
    label: "<loop>",
  }
  edges["parallel"] = { ..edges["ab"], bend: 1.0, }
  let state = { ..state, network: Some({ ..definition, edges, }), }
  let geometry = network_geometry(state, 1.0)
  assert_eq(geometry.curves.length(), 8)
  assert_true(
    geometry.curves.iter().find_first(fn(c) { c.id == "edges/loop" }).unwrap().path.contains(
      "C",
    ),
  )
  assert_true(
    geometry.curves
    .iter()
    .find_first(fn(c) { c.id == "edges/parallel" })
    .unwrap().path !=
    geometry.curves[0].path,
  )
  assert_true(diagram_markup(geometry, state, 1.0).contains("&lt;loop&gt;"))
  assert_true(network_geometry(state, 0.0).curves.is_empty())
  assert_true(!state.to_json().stringify().contains("curves"))
}

///|
test "surface faces are clipped and ordered with optional fill and cached inherited axis strokes" {
  let state = @scene.default_state(Surface)
  let definition = {
    ..state.surface.unwrap(),
    zExpression: "0",
    steps: 4,
    yaw: 0.0,
    pitch: 60.0,
    zoom: 10.0,
  }
  let state = {
    ..state,
    surface: Some(definition),
    width: 160.0,
    height: 100.0,
  }
  let geometry = surface_geometry(state, 1.0)
  assert_true(!geometry.curves.is_empty() && !geometry.limited)
  assert_eq(geometry.labels.length(), 3)
  for axis in geometry.curves.filter(fn(c) { c.id.has_prefix("axes/") }) {
    assert_true(axis.stroke is None)
  }
  let wire = surface_geometry(
    { ..state, surface: Some({ ..definition, filled: false, axes: false, }), },
    1.0,
  )
  assert_true(wire.curves.all(fn(c) { c.fill == Some("none") }))
  let solid = surface_geometry(
    {
      ..state,
      surface: Some({ ..definition, wireframe: false, axes: false, }),
    },
    1.0,
  )
  assert_true(solid.curves.all(fn(c) { c.stroke == Some("none") }))
  assert_true(surface_geometry(state, 0.0).curves.is_empty())
  let markup = diagram_markup(geometry, state, 0.5)
  assert_true(markup.contains("fill-opacity=\"0.5\""))
  assert_true(!markup.contains("NaN") && !markup.contains("Infinity"))
  assert_true(!state.to_json().stringify().contains("triangles"))
}
