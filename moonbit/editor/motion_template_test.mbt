///|
fn motion_fixture() -> @scene.Scene {
  let base = @scene.blank_scene("source", "Title")
  let object : @scene.SceneObject = {
    id: "frame",
    name: "Frame",
    kind: Rectangle,
    order: 0.0,
    groupId: None,
    parentId: None,
    clipChildren: Some(true),
    locked: false,
    image: None,
    media: None,
    playback: None,
  }
  let objects = {
    "frame": object,
    "text": {
      ..object,
      id: "text",
      name: "Title",
      kind: Text,
      order: 1.0,
      parentId: Some("frame"),
      clipChildren: None,
    },
  }
  let state = @scene.default_state(Text)
  let a = {
    ..base.compositions[base.compositionOrder[0]],
    id: "a",
    states: {
      "frame": @scene.default_state(Rectangle),
      "text": { ..state, text: "Hello", fill: "#ffffff", },
    },
  }
  let b = {
    ..a,
    id: "b",
    states: {
      "frame": a.states["frame"],
      "text": { ..a.states["text"], x: 300.0, },
    },
  }
  let track = {
    ..@scene.default_track("text", 800.0),
    keyframes: Some({
      "middle": {
        property: ObjectFill,
        at: 0.5,
        value: CurveColor("#ffffff"),
        easing: Linear,
        deleted: None,
      },
    }),
  }
  {
    ..base,
    objects,
    compositionOrder: ["a", "b"],
    compositions: { "a": a, "b": b },
    transitions: {
      "t": {
        id: "t",
        fromId: "a",
        toId: "b",
        duration: 800.0,
        tracks: { "text": track },
      },
    },
  }
}

///|
test "capture preserves motion dependencies and parameter replacement preserves authored input" {
  let source = motion_fixture()
  let captured = @editor.capture_motion(source, ["text"], "Saved title").unwrap()
  assert_eq(captured.objects.length(), 2)
  assert_true(!captured.compositions["a"].states["frame"].visible)
  assert_true(source.compositions["a"].states["frame"].visible)
  assert_eq(captured.objects["text"].parentId, Some("frame"))
  assert_true(
    @editor.motion_parameters(captured).contains(@editor.MotionText("Hello")),
  )
  let changed = @editor.replace_motion(captured, { "Hello": "Goodbye" }, {
    "#ffffff": "#ff0000",
  })
  assert_eq(changed.compositions["a"].states["text"].text, "Goodbye")
  assert_eq(changed.compositions["b"].states["text"].fill, "#ff0000")
  assert_true(
    changed.transitions["t"].tracks["text"].keyframes.unwrap()["middle"].value ==
    @scene.CurveColor("#ff0000"),
  )
  assert_eq(source.compositions["a"].states["text"].text, "Hello")
  assert_true(
    source.transitions["t"].tracks["text"].keyframes.unwrap()["middle"].value ==
    @scene.CurveColor("#ffffff"),
  )
}

///|
test "motion insertion allocates independent identities and preserves target poses" {
  let source = motion_fixture()
  let target = @scene.blank_scene("target", "Existing")
  let count = Ref(0)
  let allocate = fn(prefix : String) {
    count.val += 1
    "\{prefix}-\{count.val}"
  }
  let insertion = @editor.insert_motion(target, source, allocate).unwrap()
  assert_eq(insertion.compositions.length(), 2)
  assert_eq(insertion.objects.length(), 2)
  assert_eq(insertion.transitions.length(), 2)
  assert_eq(target.compositionOrder.length(), 1)
  for item in insertion.objects {
    assert_true(!source.objects.contains(item.object.id))
    assert_true(item.states.all(fn(item) { !item.1.visible }))
    if item.object.kind == Text {
      assert_eq(item.object.parentId, Some(insertion.objects[0].object.id))
    }
  }
  let parameters = @editor.motion_parameters(source)
  assert_true(parameters.contains(@editor.MotionColor("#ffffff")))
  let no_capacity = {
    ..target,
    compositionOrder: Array::make(100, target.compositionOrder[0]),
  }
  let before = count.val
  assert_true(@editor.insert_motion(no_capacity, source, allocate) is Err(_))
  assert_eq(before, count.val)
}
