///|
test "the pure plan reads only the edited state and leaves the source unchanged" {
  let calls = Ref(0)
  let state = @scene.default_state(Circle)
  let source : Source = {
    objects: {
      "a": {
        id: "a",
        name: "A",
        kind: Circle,
        order: 0.0,
        locked: false,
        groupId: None,
        parentId: None,
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
        state_ids: ["a"],
      },
      "second": {
        id: "second",
        name: "Second",
        duration: 1000.0,
        accent: "#ffffff",
        state_ids: ["a"],
      },
    },
    transitions: Map([]),
    order: ["first", "second"],
    raw_composition_ids: ["first", "second"],
    deleted_compositions: Set([]),
    state: fn(cid, oid) {
      calls.val += 1
      if cid == "first" && oid == "a" {
        Some(state)
      } else {
        abort("Unrelated state read")
      }
    },
    track: fn(_, _) { abort("Unrelated track read") },
  }
  let plan = compile(source, [State("first", "a", X, Number(42.0))], fn(_) {
    abort("No ID allocation needed")
  })
  assert_eq(calls.val, 1)
  assert_eq(plan.changes.length(), 1)
  assert_eq(plan.changes[0].path, ["compositions", "first", "states", "a", "x"])
  assert_true(plan.changes[0].value is ScalarValue(Number(42.0)))
  assert_eq(state.x, 640.0)
  assert_eq(source.order, ["first", "second"])
}
