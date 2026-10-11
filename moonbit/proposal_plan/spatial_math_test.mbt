///|
fn math_source(kind : @scene.ObjectKind) -> Source {
  let state = @scene.default_state(kind)
  {
    objects: {
      "diagram": {
        id: "diagram",
        name: "Diagram",
        kind,
        order: 0.0,
        locked: false,
        groupId: None,
        parentId: None,
        clipChildren: None,
        image: None,
        media: None,
        playback: None,
      },
    },
    compositions: {
      "first": {
        id: "first",
        name: "First",
        duration: 1000.0,
        accent: "#ffffff",
        state_ids: ["diagram"],
      },
    },
    transitions: Map([]),
    order: ["first"],
    raw_composition_ids: ["first"],
    deleted_compositions: Set([]),
    state: fn(cid, oid) {
      if cid == "first" && oid == "diagram" {
        Some(state)
      } else {
        abort("Unrelated state read")
      }
    },
    track: fn(_, _) { abort("Unrelated track read") },
  }
}

///|
test "pure network plans publish scalar leaves and validate final references before publication" {
  let source = math_source(Network)
  let definition = @scene.default_network()
  let plan = compile(
    source,
    [
      NetworkElement(
        "first",
        "diagram",
        "nodes",
        "a",
        Some(NodeElement({ ..definition.nodes["a"], x: 5.0, })),
      ),
    ],
    fn(_) { abort("No identity allocation") },
  )
  assert_eq(plan.changes.length(), 1)
  assert_eq(plan.changes[0].path, [
    "compositions", "first", "states", "diagram", "network", "nodes", "a", "x",
  ])
  assert_true(plan.changes[0].value is ScalarValue(Number(5.0)))
  assert_eq(
    (source.state)("first", "diagram").unwrap().network.unwrap().nodes["a"].x,
    -2.0,
  )
  let operation : Operation = NetworkElement(
    "first",
    "diagram",
    "edges",
    "loop",
    Some(
      EdgeElement({
        ..definition.edges["ab"],
        from: "p",
        to: "p",
        weight: None,
      }),
    ),
  )
  let accepted = compile(
    source,
    [
      operation,
      NetworkElement(
        "first",
        "diagram",
        "nodes",
        "p",
        Some(NodeElement({ x: 0.0, y: 0.0, label: "P", deleted: None, })),
      ),
    ],
    fn(_) { abort("No identity allocation") },
  )
  assert_eq(accepted.changes.length(), 2)
  assert_true(
    try {
      compile(source, [operation], fn(_) { abort("No identity allocation") })
      |> ignore
      false
    } catch {
      CompileError(_) => true
    },
  )
}

///|
test "surface plans preserve unchanged cameras and guard coupled fields" {
  let source = math_source(Surface)
  let definition = @scene.default_surface()
  let plan = compile(
    source,
    [
      SurfaceDefinition("first", "diagram", {
        ..definition,
        zExpression: "x*y",
        a: 2.0,
      }),
    ],
    fn(_) { abort("No identity allocation") },
  )
  assert_eq(plan.changes.length(), 2)
  assert_true(
    plan.changes.all(fn(change) {
      ["a", "zExpression"].contains(change.path.last().unwrap())
    }),
  )
  assert_true(!plan.guards.any(fn(path) { path.contains("yaw") }))
  let range = compile(
    source,
    [SurfaceDefinition("first", "diagram", { ..definition, uMin: 1.0, })],
    fn(_) { abort("No identity allocation") },
  )
  assert_true(range.guards.any(fn(path) { path.last() == Some("uMax") }))
  assert_true(
    try {
      compile(
        source,
        [
          SurfaceDefinition("first", "diagram", {
            ..definition,
            filled: false,
            wireframe: false,
          }),
        ],
        fn(_) { abort("No identity allocation") },
      )
      |> ignore
      false
    } catch {
      CompileError(_) => true
    },
  )
}
