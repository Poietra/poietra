///|
fn resource_object(id : String, kind : @scene.ObjectKind) -> @scene.SceneObject {
  {
    id,
    name: id,
    kind,
    order: 0.0,
    groupId: None,
    locked: false,
    parentId: None,
    clipChildren: None,
    image: None,
    media: None,
    playback: None,
  }
}

///|
test "prepared resources include retained states and preserve first ordered Scene dimensions" {
  let a = @scene.blank_scene("a", "A")
  a.objects["text"] = resource_object("text", Text)
  a.objects["math"] = resource_object("math", Equation)
  a.objects["shape"] = resource_object("shape", Circle)
  let live = a.compositions["a-comp-1"]
  live.states["text"] = {
    ..@scene.default_state(Text),
    text: "日本語",
    visible: false,
  }
  live.states["math"] = { ..@scene.default_state(Equation), text: "x^2", }
  live.states["shape"] = {
    ..@scene.default_state(Circle),
    text: "unused shape text",
  }
  live.states["orphan"] = { ..@scene.default_state(Text), text: "orphan text", }
  let retained = {
    ..@scene.empty_composition("retained", "Retained", 100.0, "#ffffff"),
    deleted: Some(true),
  }
  retained.states["text"] = {
    ..@scene.default_state(Text),
    text: "retained text",
  }
  retained.states["math"] = { ..@scene.default_state(Equation), text: "y^2", }
  a.compositions["retained"] = retained
  let b = { ..@scene.blank_scene("b", "B"), width: 640.0, height: 360.0, }
  b.objects["text"] = resource_object("text", Text)
  b.compositions["b-comp-1"].states["text"] = {
    ..@scene.default_state(Text),
    text: "日本語",
  }
  let ignored = @scene.blank_scene("ignored", "Not ordered")
  ignored.objects["text"] = resource_object("text", Text)
  ignored.compositions["ignored-comp-1"].states["text"] = {
    ..@scene.default_state(Text),
    text: "not ordered",
  }
  let timeline = prepare(
    {
      version: 2,
      name: "Resources",
      sceneOrder: ["missing", "b", "a"],
      scenes: Map([("a", a), ("b", b), ("ignored", ignored)]),
    },
    fn(a, b) { a.compare(b) },
  )
  let inspection = timeline.inspect()
  assert_eq(
    (inspection.scenes, inspection.width, inspection.height),
    (2, 640.0, 360.0),
  )
  let first = timeline.preparation()
  let expected = ["retained text", "日本語"]
  expected.sort()
  first.texts.sort()
  first.equations.sort()
  assert_eq(first.texts, expected)
  assert_eq(first.equations, ["x^2", "y^2"])
  // A backend can consume or change its own lists without damaging later renders.
  first.texts.clear()
  first.equations[0] = "changed by backend"
  let second = timeline.preparation()
  second.texts.sort()
  second.equations.sort()
  assert_eq(second.texts, expected)
  assert_eq(second.equations, ["x^2", "y^2"])
}

///|
test "shape-only timelines require no text resources" {
  let scene = @scene.blank_scene("scene", "Shapes")
  scene.objects["circle"] = resource_object("circle", Circle)
  scene.compositions["scene-comp-1"].states["circle"] = {
    ..@scene.default_state(Circle),
    text: "unused",
  }
  let timeline = prepare(
    {
      version: 1,
      name: "Shapes",
      sceneOrder: ["scene"],
      scenes: Map([("scene", scene)]),
    },
    fn(a, b) { a.compare(b) },
  )
  assert_eq(timeline.preparation().texts, [])
  assert_eq(timeline.preparation().equations, [])
}
