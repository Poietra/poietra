///|
test "networks accept loops and parallel edges but reject orphan endpoints and oversized definitions" {
  let network = @scene.default_network()
  let edges = network.edges.copy()
  edges["loop"] = {
    ..edges["ab"],
    from: "a",
    to: "a",
    directed: true,
    weight: None,
  }
  edges["parallel"] = { ..edges["ab"], bend: 1.0, }
  let network = { ..network, edges, }
  assert_true(@scene.network_validation_error(network) is None)
  assert_eq(@scene.network_degree(network, "a"), {
    incoming: 2,
    outgoing: 1,
    undirected: 2,
  })
  let nodes = network.nodes.copy()
  nodes["a"] = { ..nodes["a"], deleted: Some(true), }
  assert_true(@scene.network_validation_error({ ..network, nodes, }) is Some(_))
  let nodes = Map::from_iter(
    Array::makei(129, fn(i) { ("n" + i.to_string(), network.nodes["a"]) }).iter(),
  )
  assert_true(@scene.network_validation_error({ ..network, nodes, }) is Some(_))
  let restored : @scene.NetworkDefinition = @json.from_json(network.to_json())
  assert_true(restored == network)
}

///|
test "surface presets remain portable while invalid formulas and views fail validation" {
  for name in ["wave", "saddle", "sphere", "torus"] {
    let definition = @scene.surface_preset(name)
    assert_true(@scene.surface_validation_error(definition) is None)
    let restored : @scene.SurfaceDefinition = @json.from_json(
      definition.to_json(),
    )
    assert_true(restored == definition)
  }
  let d = @scene.default_surface()
  for
    invalid in [
      { ..d, steps: 49, },
      { ..d, steps: 3, },
      { ..d, zoom: 0.01, },
      { ..d, pitch: 90.0, },
      { ..d, yaw: 1.0 / 0.0, },
      { ..d, uMin: d.uMax, },
      { ..d, filled: false, wireframe: false, },
      { ..d, zExpression: "globalThis.alert(1)", },
      { ..d, zExpression: "x=y", },
    ] {
    assert_true(@scene.surface_validation_error(invalid) is Some(_))
  }
}

///|
test "network positions and surface view coefficients follow position timing with discrete topology" {
  let base = @scene.blank_scene("s", "Mathematics")
  let first = base.compositions[base.compositionOrder[0]]
  let n = @scene.default_network()
  let nodes = n.nodes.copy()
  nodes["a"] = { ..nodes["a"], x: 2.0, y: 3.0, }
  let edges = n.edges.copy()
  edges["ab"] = { ..edges["ab"], directed: true, weight: Some(9.0), }
  let d = @scene.default_surface()
  let from = {
    ..first,
    states: {
      "n": @scene.default_state(Network),
      "s": @scene.default_state(Surface),
    },
  }
  let to = {
    ..from,
    id: "end",
    states: {
      "n": { ..from.states["n"], network: Some({ ..n, nodes, edges, }), },
      "s": {
        ..from.states["s"],
        surface: Some({
          ..d,
          a: 3.0,
          yaw: 95.0,
          pitch: 55.0,
          zoom: 2.0,
          zExpression: "a*(x^2-y^2)",
          steps: 24,
        }),
      },
    },
  }
  let track = fn(id) {
    {
      ..@scene.default_track(id, 1000.0),
      easing: Linear,
      positionTiming: Some({ start: 200.0, duration: 400.0, easing: Linear, }),
    }
  }
  let scene : @scene.Scene = {
    ..base,
    objects: {
      "n": { ..object("n", None), kind: Network, },
      "s": { ..object("s", None), kind: Surface, },
    },
    compositions: Map([(from.id, from), (to.id, to)]),
    compositionOrder: [from.id, to.id],
    transitions: {
      "t": {
        id: "t",
        fromId: from.id,
        toId: to.id,
        duration: 1000.0,
        tracks: { "n": track("n"), "s": track("s") },
      },
    },
  }
  let prepared = @scene.prepare_scene(scene, kernel())
  let frame = prepared.transition("t", 400.0, None)
  let network = frame.objects
  .iter()
  .find_first(fn(o) { o.object.kind == Network })
  .unwrap().state.network.unwrap()
  near(network.nodes["a"].x, 0.0)
  near(network.nodes["a"].y, 1.0)
  assert_true(!network.edges["ab"].directed)
  let surface = frame.objects
  .iter()
  .find_first(fn(o) { o.object.kind == Surface })
  .unwrap().state.surface.unwrap()
  near(surface.a, 2.0)
  near(surface.yaw, 65.0)
  near(surface.pitch, 45.0)
  near(surface.zoom, 1.5)
  assert_eq(surface.zExpression, d.zExpression)
  let later = prepared.transition("t", 500.0, None)
  assert_eq(
    later.objects.iter().find_first(fn(o) { o.object.kind == Network }).unwrap().state.network.unwrap().edges["ab"].weight,
    Some(9.0),
  )
  assert_eq(
    later.objects.iter().find_first(fn(o) { o.object.kind == Surface }).unwrap().state.surface.unwrap().steps,
    24,
  )
  assert_true(from.states["n"].network.unwrap() == n)
}
