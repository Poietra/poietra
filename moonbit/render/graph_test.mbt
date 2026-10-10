///|
test "render cache owns its discontinuities and does not expose mutable label storage" {
  let graph = {
    ..@scene.default_graph(),
    expression: "floor(x-0.123)",
    xMin: -0.5,
    xMax: 0.5,
    yMin: -2.0,
    yMax: 2.0,
  }
  let state = { ..@scene.default_state(Graph), graph: Some(graph), }
  let first = graph_geometry(state, 1.0)
  assert_true(first.limited)
  assert_true(first.labels.length() > 0)
  first.labels.clear()
  assert_true(graph_geometry(state, 1.0).labels.length() > 0)
  graph.breaks.push(0.123)
  assert_true(!graph_geometry(state, 1.0).limited)
  assert_true(graph_geometry(state, 0.0).curve.is_empty())
  assert_true(
    graph_geometry(state, 0.5).curve.length() <
    graph_geometry(state, 1.0).curve.length(),
  )
}
