///|
test "manual insertion keeps composition visibility, kind counts and implicit timing" {
  let target : ObjectCreationTarget = {
    objects: [
      (@scene.Circle, 20.0),
      (@scene.Rectangle, 2.0),
      (@scene.Circle, 1.0),
    ],
    compositions: ["a", "b", "c"],
    transitions: [("ab", 800.0), ("bc", 0.0)],
  }
  let state = { ..@scene.default_state(Circle), x: 42.0, visible: false, }
  let result = create_object(target, "b", Circle, state, None, None, fn(
    prefix,
  ) {
    prefix + "-new"
  })
  guard result is Ok(result) else { fail("Expected an insertion plan") }
  assert_eq(result.object.id, "obj-new")
  assert_eq(result.object.name, "Circle 3")
  assert_eq(result.object.order, 21.0)
  assert_eq(result.object.locked, false)
  assert_eq(result.object.groupId, None)
  assert_eq(result.states.map(fn(entry) { entry.1.visible }), [
    false, true, false,
  ])
  assert_eq(result.states.map(fn(entry) { entry.1.x }), [42.0, 42.0, 42.0])
  assert_eq(result.tracks.map(fn(entry) { entry.1.duration }), [800.0, 0.0])
  assert_true(
    result.tracks.all(fn(entry) {
      entry.1.implicit == Some(true) && entry.1.objectId == "obj-new"
    }),
  )
  assert_eq(state.visible, false)
}

///|
test "manual creation validates the complete target before allocating an identity" {
  let target : ObjectCreationTarget = {
    objects: Array::make(500, (@scene.Circle, 0.0)),
    compositions: ["a"],
    transitions: [],
  }
  let allocated = Ref(0)
  let allocate = fn(_) {
    allocated.val += 1
    "new"
  }
  let state = @scene.default_state(Circle)
  assert_true(
    create_object(target, "gone", Circle, state, None, None, allocate)
    is Err(MissingComposition),
  )
  assert_true(
    create_object(target, "a", Circle, state, None, None, allocate)
    is Err(ObjectLimit),
  )
  assert_eq(allocated.val, 0)
  assert_true(
    create_object(
      { ..target, objects: Array::make(499, (@scene.Circle, 0.0)), },
      "a",
      Circle,
      state,
      None,
      None,
      allocate,
    )
    is Ok(_),
  )
  assert_eq(allocated.val, 1)
}

///|
test "image creation retains asset metadata and the bounded custom name" {
  let target : ObjectCreationTarget = {
    objects: [],
    compositions: ["a"],
    transitions: [],
  }
  let image : @scene.ImageAsset = { src: "/image", width: 32.0, height: 64.0, }
  let result = create_object(
    target,
    "a",
    Image,
    @scene.default_state(Image),
    Some(image),
    Some("x".repeat(201)),
    fn(_) { "new" },
  )
  guard result is Ok(result) else { fail("Expected an image insertion") }
  assert_eq(result.object.name.length(), 200)
  assert_eq(result.object.image.unwrap().src, "/image")
  assert_eq(result.object.order, 0.0)
}

///|
test "drag and hide exclude locked objects, deleted objects and absent states" {
  let point : @scene.Point = { x: 10.0, y: 20.0, }
  let targets : Array[StateTarget[@scene.Point]] = [
    { id: "ready", locked: Some(false), state: Some(point), },
    { id: "locked", locked: Some(true), state: Some(point), },
    { id: "deleted", locked: None, state: Some(point), },
    { id: "absent", locked: Some(false), state: None, },
  ]
  assert_eq(editable_state_ids(targets), ["ready"])
  let moved = translated_objects(targets, 1.25, -2.25)
  assert_eq(moved.length(), 1)
  assert_eq(moved[0].0, "ready")
  assert_true(moved[0].1 == { x: 11.3, y: 17.8, })
  assert_true(targets[0].state == Some(point))
}

///|
test "drag snapping preserves half-up rounding, signed zero and nonfinite values on every target" {
  let shifted = fn(x, y) {
    translated_objects(
      [{ id: "a", locked: Some(false), state: Some({ x, y, }), }],
      0.0,
      0.0,
    )[0].1
  }
  assert_true(shifted(1.05, -1.05) == { x: 1.1, y: -1.0, })
  let tiny = shifted(-0.05, 0.04999999999999999)
  assert_eq(1.0 / tiny.x, -1.0 / 0.0)
  assert_eq(1.0 / tiny.y, 1.0 / 0.0)
  let nonfinite = shifted(0.0 / 0.0, 1.0 / 0.0)
  assert_true(nonfinite.x.is_nan())
  assert_eq(nonfinite.y, 1.0 / 0.0)
}

///|
test "group expansion preserves scene order and cannot expand from a locked selection" {
  let objects : Array[GroupObject] = [
    { id: "b", group_id: Some("g"), locked: false, order: 2.0, },
    { id: "a", group_id: Some("g"), locked: false, order: 1.0, },
    { id: "locked", group_id: Some("g"), locked: true, order: 0.0, },
    { id: "empty", group_id: Some(""), locked: false, order: 0.0, },
    { id: "another-empty", group_id: Some(""), locked: false, order: 0.0, },
  ]
  assert_eq(editable_group_members(objects, ["a", "a", "missing", "empty"]), [
    "b", "a", "empty",
  ])
  assert_eq(editable_group_members(objects, ["locked"]), [])
  assert_eq(group_members(objects, "g"), ["locked", "a", "b"])
}

///|
test "animation selection classifies presence once with stable deduplication and exclusion priority" {
  let candidates : Array[AnimationCandidate] = [
    { id: "enter", locked: false, from_visible: false, to_visible: true, },
    { id: "hidden", locked: false, from_visible: false, to_visible: false, },
    { id: "both", locked: false, from_visible: true, to_visible: true, },
    { id: "locked", locked: true, from_visible: false, to_visible: false, },
    { id: "exit", locked: false, from_visible: true, to_visible: false, },
  ]
  let result = select_animations([..candidates, candidates[0], candidates[1]])
  assert_true(
    result.targets == [("enter", Entering), ("both", Both), ("exit", Leaving)],
  )
  assert_eq(result.excluded, [("hidden", Hidden), ("locked", Locked)])
}
