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

///|
test "equation geometry owns one connected circle and invalidates coefficients and grammar" {
  let graph = {
    ..@scene.default_graph(),
    expression: "x^2+y^2=a^2",
    a: 1.0,
    xMin: -2.0,
    xMax: 2.0,
    yMin: -2.0,
    yMax: 2.0,
  }
  let invalid = {
    ..@scene.default_state(Graph),
    graph: Some(graph),
    width: 400.0,
    height: 400.0,
  }
  assert_true(graph_geometry(invalid, 1.0).curve.is_empty())
  let state = { ..invalid, graph: Some({ ..graph, syntaxVersion: 2, }), }
  let full = graph_geometry(state, 1.0)
  assert_true(!full.limited)
  assert_true(!full.curve.is_empty())
  assert_eq(full.curve.split("M").count(), 2)
  assert_true(graph_geometry(state, 0.5).curve.length() < full.curve.length())
  assert_true(graph_geometry(state, 0.0).curve.is_empty())
  assert_true(
    graph_geometry(
      { ..state, graph: Some({ ..graph, syntaxVersion: 2, a: 1.5, }), },
      1.0,
    ).curve !=
    full.curve,
  )
  assert_eq(graph_geometry(state, 1.0).curve, full.curve)
}

///|
test "a filled function shades each branch down to the clamped x-axis and reveals it with the curve" {
  let graph = {
    ..@scene.default_graph(),
    expression: "1/x",
    breaks: [0.0],
    axes: false,
    grid: false,
    xMin: -2.0,
    xMax: 2.0,
    yMin: -2.0,
    yMax: 2.0,
  }
  let state = {
    ..@scene.default_state(Graph),
    graph: Some(graph),
    width: 400.0,
    height: 200.0,
  }
  assert_eq(graph_geometry(state, 1.0).area, "")
  let filled = { ..state, graph: Some({ ..graph, filled: Some(true), }), }
  let full = graph_geometry(filled, 1.0)
  assert_eq(full.curve, graph_geometry(state, 1.0).curve)
  // Two branches around the pole, each closed on the axis at y = 0.
  assert_eq(full.area.split("Z").count(), 3)
  assert_eq(full.area.split("M").count(), 3)
  assert_true(full.area.contains(" 0Z"))
  let half = graph_geometry(filled, 0.5)
  assert_true(half.area.length() < full.area.length())
  assert_true(half.area.length() > 0)
  assert_eq(graph_geometry(filled, 0.0).area, "")
  // An axis outside the viewport clamps the baseline to the viewport edge.
  let above = {
    ..filled,
    graph: Some({ ..graph, filled: Some(true), yMin: 1.0, yMax: 3.0, }),
  }
  assert_true(graph_geometry(above, 1.0).area.contains(" 100Z"))
  // The region below an equation is undefined, so implicit curves never shade.
  let implicit = {
    ..filled,
    graph: Some({
      ..graph,
      filled: Some(true),
      syntaxVersion: 2,
      expression: "x^2+y^2=1",
      breaks: [],
    }),
  }
  assert_true(!graph_geometry(implicit, 1.0).curve.is_empty())
  assert_eq(graph_geometry(implicit, 1.0).area, "")
}
