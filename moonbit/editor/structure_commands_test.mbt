///|
test "scene creation keeps the visible survivor and allocates independent defaults" {
  let order = ["first", "second"]
  guard plan_scene_append(order, fn(prefix) { prefix + "-new" }) is Ok(plan) else {
    fail("Expected scene creation")
  }
  assert_eq(plan.retained_id, Some("first"))
  assert_eq(plan.value.id, "scene-new")
  assert_eq(plan.value.name, "Scene 3")
  assert_eq(plan.value.compositionOrder, ["scene-new-comp-1"])
  assert_eq(plan.value.width, 1280.0)
  assert_eq(plan.value.height, 720.0)
  assert_eq(plan.value.background, "#08090b")
  assert_true(plan.value.objects.is_empty())
  assert_true(plan.value.audioTracks.unwrap().is_empty())
  assert_eq(order, ["first", "second"])
  let initial = plan.value.compositions["scene-new-comp-1"]
  assert_eq(initial.name, "Composition 1")
  assert_eq(initial.duration, 1000.0)
  assert_eq(initial.accent, "#f4ce55")
}

///|
test "composition creation plans inherited state identity and implicit animations" {
  guard plan_composition_append(
      3,
      Some("source"),
      ["circle", "text"],
      ["#ff0000", "#00ff00"],
      fn(prefix) { prefix + "-new" },
    )
    is Ok(plan) else {
    fail("Expected composition creation")
  }
  assert_eq(plan.source_id, Some("source"))
  assert_eq(plan.value.id, "comp-new")
  assert_eq(plan.value.name, "Composition 4")
  assert_eq(plan.value.duration, 1000.0)
  assert_eq(plan.value.accent, "#00ff00")
  assert_true(plan.value.states.is_empty())
  let transition = plan.incoming.unwrap()
  assert_eq(transition.id, "transition-new")
  assert_eq(transition.fromId, "source")
  assert_eq(transition.toId, "comp-new")
  assert_eq(transition.duration, 800.0)
  assert_eq(transition.tracks.length(), 2)
  for id in ["circle", "text"] {
    let track = transition.tracks[id]
    assert_eq(track.objectId, id)
    assert_eq(track.implicit, Some(true))
    assert_eq(track.start, 0.0)
    assert_eq(track.duration, 800.0)
    assert_true(track.type_ == Move && track.easing == EaseInOut)
  }
}

///|
test "an empty scene creates no dangling transition and preserves identity allocation order" {
  let allocated : Array[String] = []
  guard plan_composition_append(0, None, [], ["#ffffff"], fn(prefix) {
      allocated.push(prefix)
      prefix + "-new"
    })
    is Ok(plan) else {
    fail("Expected first composition")
  }
  assert_true(plan.source_id is None && plan.incoming is None)
  assert_eq(plan.value.name, "Composition 1")
  assert_true(plan.value.states.is_empty())
  assert_eq(allocated, ["comp", "transition"])
}

///|
test "structure limits reject creation before identity allocation" {
  let allocations = Ref(0)
  let allocate = fn(prefix) {
    allocations.val += 1
    prefix + "-new"
  }
  assert_true(
    plan_scene_append(Array::make(100, "existing"), allocate) is Err(SceneLimit),
  )
  assert_true(
    plan_composition_append(100, None, [], [], allocate)
    is Err(CompositionLimit),
  )
  assert_eq(allocations.val, 0)
  assert_true(plan_scene_append(Array::make(99, "existing"), allocate) is Ok(_))
  assert_true(
    plan_composition_append(99, None, [], ["#ffffff"], allocate) is Ok(_),
  )
  assert_eq(allocations.val, 3)
}

///|
test "an empty palette cannot produce an invalid Composition" {
  let allocations = Ref(0)
  assert_true(
    plan_composition_append(1, Some("source"), [], [], fn(_) {
      allocations.val += 1
      "unused"
    })
    is Err(EmptyPalette),
  )
  assert_eq(allocations.val, 0)
}

///|
test "scene factories never share mutable maps or order arrays" {
  let first = @scene.blank_scene("s", "Scene")
  let second = @scene.blank_scene("s", "Scene")
  first.compositionOrder.push("extra")
  first.compositions["s-comp-1"].states["circle"] = @scene.default_state(Circle)
  first.compositions["extra"] = @scene.empty_composition(
    "extra", "Extra", 0.0, "#ffffff",
  )
  assert_eq(second.compositionOrder, ["s-comp-1"])
  assert_eq(second.compositions.length(), 1)
  assert_true(second.compositions["s-comp-1"].states.is_empty())
  let left = @scene.implicit_transition("t", "a", "b", 800.0, ["circle"])
  let right = @scene.implicit_transition("t", "a", "b", 800.0, ["circle"])
  left.tracks["circle"] = { ..left.tracks["circle"], duration: 100.0, }
  assert_eq(right.tracks["circle"].duration, 800.0)
}
