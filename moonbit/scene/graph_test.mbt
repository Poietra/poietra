///|
test "function definitions remain independent per Composition and coefficients follow their own timing" {
  let base = @scene.blank_scene("graph-scene", "Functions")
  let definition = @scene.default_graph()
  let first = base.compositions[base.compositionOrder[0]]
  let from = { ..first, states: { "g": @scene.default_state(Graph) }, }
  let to = {
    ..first,
    id: "end",
    states: {
      "g": {
        ..@scene.default_state(Graph),
        graph: Some({
          ..definition,
          a: 7.0,
          b: 4.0,
          c: -2.0,
          expression: "a*x+b+c",
        }),
      },
    },
  }
  let track = {
    ..@scene.default_track("g", 1000.0),
    easing: Linear,
    graphTiming: Some({ start: 200.0, duration: 400.0, easing: Linear, }),
    keyframes: Some({
      "middle": {
        property: GraphA,
        at: 0.5,
        value: CurveNumber(9.0),
        easing: Linear,
        deleted: None,
      },
    }),
  }
  let scene : @scene.Scene = {
    ..base,
    objects: { "g": { ..object("g", None), kind: Graph, } },
    compositionOrder: [from.id, to.id],
    compositions: Map([(from.id, from), (to.id, to)]),
    transitions: {
      "t": {
        id: "t",
        fromId: from.id,
        toId: to.id,
        duration: 1000.0,
        tracks: { "g": track },
      },
    },
  }
  let prepared = @scene.prepare_scene(scene, kernel())
  for
    (time, a, b) in [
      (100.0, 3.0, 0.0),
      (300.0, 6.0, 1.0),
      (400.0, 9.0, 2.0),
      (500.0, 8.0, 3.0),
      (600.0, 7.0, 4.0),
    ] {
    let frame = prepared.transition("t", time, None)
    let graph = frame.objects[0].state.graph.unwrap()
    near(graph.a, a)
    near(graph.b, b)
    near(graph.c, -b / 2.0)
    assert_eq(
      graph.expression,
      if time < 500.0 {
        definition.expression
      } else {
        "a*x+b+c"
      },
    )
  }
  assert_eq(
    prepared.composition(from.id, None).objects[0].state.graph.unwrap().a,
    3.0,
  )
  assert_eq(
    prepared.composition(to.id, None).objects[0].state.graph.unwrap().a,
    7.0,
  )
  let restored : @scene.Scene = @json.from_json(scene.to_json())
  assert_eq(
    restored.transitions["t"].tracks["g"].graphTiming.unwrap().start,
    200.0,
  )
}

///|
test "graph validation rejects incompatible syntax, invalid ranges and code without host evaluation" {
  let graph = @scene.default_graph()
  for
    invalid in [
      { ..graph, syntaxVersion: 3, },
      { ..graph, xMin: graph.xMax, },
      { ..graph, yMax: graph.yMin, },
      { ..graph, a: 1.0 / 0.0, },
      { ..graph, expression: "globalThis.process.exit()", },
    ] {
    assert_true(@scene.graph_validation_error(invalid) is Some(_))
  }
  assert_true(
    @scene.graph_validation_error({
      ..graph,
      expression: "sqrt(x)",
      breaks: [0.0],
    })
    is None,
  )
  assert_eq(@scene.parse_graph_breaks(" -1, 0.123, 2 "), [-1.0, 0.123, 2.0])
}

///|
test "implicit definitions keep an explicit grammar version and portable equation" {
  let graph = @scene.default_graph()
  for expression in ["x^2+y^2=a^2", "y^2=x^3-x", "x*y=b", "x=1"] {
    let definition = {
      ..graph,
      expression,
      syntaxVersion: @scene.graph_expression_version(expression),
    }
    assert_eq(definition.syntaxVersion, 2)
    assert_true(@scene.graph_validation_error(definition) is None)
    let restored : @scene.GraphDefinition = @json.from_json(
      definition.to_json(),
    )
    assert_true(restored == definition)
    assert_true(
      @scene.graph_validation_error({ ..definition, syntaxVersion: 1, })
      is Some(_),
    )
  }
  for
    definition in [
      { ..graph, syntaxVersion: 3, },
      { ..graph, syntaxVersion: 2, expression: "x==y", },
    ] {
    assert_true(@scene.graph_validation_error(definition) is Some(_))
  }
}
