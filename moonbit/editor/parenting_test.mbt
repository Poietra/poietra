///|
test "reparent plans preserve both retained and active poses and keep input immutable" {
  let object : @scene.SceneObject = {
    id: "child",
    name: "Child",
    kind: Rectangle,
    order: 0.0,
    groupId: None,
    parentId: None,
    locked: false,
    image: None,
    media: None,
    playback: None,
  }
  let child = {
    ..@scene.default_state(Rectangle),
    x: 140.0,
    y: 170.0,
    rotation: 48.0,
    anchorX: Some(10.0),
  }
  let parent = {
    ..child,
    x: 700.0,
    rotation: -37.0,
    scaleX: Some(2.7),
    scaleY: Some(0.6),
  }
  let first = {
    ..@scene.empty_composition("first", "First", 1000.0, "#fff"),
    states: { "child": child, "parent": parent },
  }
  let retained = {
    ..first,
    id: "retained",
    deleted: Some(true),
    states: {
      "child": { ..child, x: 970.0, },
      "parent": { ..parent, rotation: 99.0, },
    },
  }
  let scene = {
    ..@scene.blank_scene("s", "Scene"),
    objects: { "child": object, "parent": { ..object, id: "parent", } },
    compositions: { "first": first, "retained": retained },
    compositionOrder: ["first"],
  }
  let plan = @editor.plan_reparent(scene, "child", Some("parent")).unwrap()
  assert_eq(plan.states.length(), 2)
  for (cid, next) in plan.states {
    let before = scene.compositions[cid].states["child"].local_matrix()
    let after = scene.compositions[cid].states["parent"]
      .local_matrix()
      .compose(next.local_matrix())
    for
      point in [
        @scene.Point::{ x: -35.0, y: -20.0, },
        @scene.Point::{ x: 35.0, y: 20.0, },
      ] {
      let a = before.point(point)
      let b = after.point(point)
      assert_true((a.x - b.x).abs() < 1.0e-8 && (a.y - b.y).abs() < 1.0e-8)
    }
  }
  assert_eq(scene.objects["child"].parentId, None)
  let anchor = @editor.move_anchor(child, 25.0, -17.0)
  assert_true((anchor.local_matrix().e - child.local_matrix().e).abs() < 1.0e-8)
  let movements = @editor.project_world_moves(
    [
      {
        id: "parent",
        start: { x: 5.0, y: 10.0, },
        delta: { x: 40.0, y: 20.0, },
      },
      { id: "child", start: { x: 2.0, y: 3.0, }, delta: { x: 40.0, y: 20.0, }, },
    ],
    { "child": "parent" },
    fn(_) { Some(@scene.Affine::identity()) },
  )
  assert_eq(movements.length(), 1)
  assert_eq(movements[0].0, "parent")
  assert_true(movements[0].1 == @scene.Point::{ x: 45.0, y: 30.0, })
}
