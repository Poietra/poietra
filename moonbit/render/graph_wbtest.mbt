///|
test "graph markup shades the region beneath the curve with the curve colour and keeps it under the line" {
  let graph = {
    ..@scene.default_graph(),
    expression: "x",
    filled: Some(true),
    xMin: -2.0,
    xMax: 2.0,
    yMin: -2.0,
    yMax: 2.0,
  }
  let state = {
    ..@scene.default_state(Graph),
    graph: Some(graph),
    stroke: "#67c4d9",
    width: 400.0,
    height: 200.0,
  }
  let markup = graph_markup(graph_geometry(state, 0.5), state, 0.5)
  // Half of y = x is revealed: the run starts at the lower-left corner and the
  // region closes along the x-axis back to that corner, directly under the curve.
  assert_true(markup.contains("<path data-graph-area=\"true\" d=\"M-200 100L"))
  assert_true(
    markup.contains(
      "L-200 0Z\" fill=\"#67c4d9\" fill-opacity=\"0.125\" stroke=\"none\"/><path data-graph-curve=\"true\"",
    ),
  )
  let plain = { ..state, graph: Some({ ..graph, filled: Some(false), }), }
  let unshaded = graph_markup(graph_geometry(plain, 1.0), plain, 1.0)
  assert_true(!unshaded.contains("data-graph-area"))
  assert_true(unshaded.contains("data-graph-curve"))
}
