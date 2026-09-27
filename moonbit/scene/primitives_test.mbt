///|
fn near(a : Double, b : Double) -> Unit raise {
  assert_true((a - b).abs() < 1.0e-8)
}

///|
fn kernel() -> @scene.Kernel {
  {
    track_progress: @motion.track_progress,
    interpolate: @motion.interpolate,
    cubic_bezier: @motion.cubic_bezier,
    cubic_bezier_ease: @motion.cubic_bezier_ease,
    compare_ids: fn(a, b) { a.compare(b) },
  }
}

///|
fn object(id : String, parent : String?) -> @scene.SceneObject {
  {
    id,
    parentId: parent,
    clipChildren: None,
    name: id,
    kind: Rectangle,
    order: 0.0,
    groupId: None,
    locked: false,
    image: None,
    media: None,
    playback: None,
  }
}

///|
test "hidden nested clip parents retain animated world geometry on both targets" {
  let base = @scene.blank_scene("s", "Clipping")
  let a = @scene.default_state(Rectangle)
  let states : Map[String, @scene.ObjectState] = {
    "outer": {
      ..a,
      x: 100.0,
      y: 80.0,
      width: 80.0,
      height: 80.0,
      visible: false,
    },
    "inner": {
      ..a,
      x: 10.0,
      y: 0.0,
      width: 40.0,
      height: 40.0,
      visible: false,
    },
    "child": { ..a, x: 0.0, y: 0.0, visible: true, },
  }
  let from = { ..base.compositions[base.compositionOrder[0]], states, }
  let end_states = states.copy()
  end_states["outer"] = { ..states["outer"], x: 120.0, width: 20.0, }
  let to = { ..from, id: "b", states: end_states, }
  let scene : @scene.Scene = {
    ..base,
    objects: {
      "outer": { ..object("outer", None), clipChildren: Some(true), },
      "inner": { ..object("inner", Some("outer")), clipChildren: Some(true), },
      "child": object("child", Some("inner")),
    },
    compositions: Map([(from.id, from), ("b", to)]),
    compositionOrder: [from.id, "b"],
    transitions: {
      "t": @scene.implicit_transition("t", from.id, "b", 800.0, [
        "outer", "inner", "child",
      ]),
    },
  }
  let prepared = @scene.prepare_scene(scene, kernel())
  let start = prepared.composition(from.id, None).objects
  assert_eq(start.length(), 1)
  let clips = start[0].clips.unwrap()
  assert_eq(clips.length(), 2)
  near(clips[0].world.e, 100.0)
  near(clips[1].world.e, 110.0)
  let end = prepared.transition("t", 800.0, None).objects[0].clips.unwrap()
  near(end[0].width, 20.0)
  near(end[1].world.e, 130.0)
}

///|
test "write order retains the saved string representation through typed track roundtrips" {
  for order in [@scene.Together, @scene.Sequential] {
    let track = { ..@scene.default_track("object", 1000.0), order, }
    let saved = track.to_json()
    let restored : @scene.Track = @json.from_json(saved)
    assert_true(restored.order == order)
    assert_eq(restored.to_json(), saved)
    let name = @scene.write_order_name(order)
    assert_true(saved is { "order": String(value), .. } && value == name)
  }
}

///|
test "new authored tracks own independent key containers" {
  let first = @scene.default_track("a", 1000.0)
  let second = @scene.default_track("b", 1000.0)
  first.keyframes.unwrap()["point"] = {
    property: PositionX,
    at: 0.5,
    value: CurveNumber(13.0),
    easing: Linear,
    deleted: None,
  }
  assert_eq(second.keyframes.unwrap().length(), 0)
}

///|
test "nested nonuniform rotation retains shear and reparent decomposition preserves all corners" {
  let parent = {
    ..@scene.default_state(Rectangle),
    x: 180.0,
    y: 70.0,
    rotation: 33.0,
    scaleX: Some(2.0),
    scaleY: Some(-0.75),
    anchorX: Some(19.0),
  }
  let child = {
    ..@scene.default_state(Rectangle),
    x: 41.0,
    y: -13.0,
    rotation: -27.0,
    scaleX: Some(0.8),
    anchorY: Some(-22.0),
  }
  let matrix = parent.local_matrix().compose(child.local_matrix())
  let decomposed = child.with_matrix(matrix).local_matrix()
  let inverse = matrix.inverse().unwrap()
  for
    point in [
      @scene.Point::{ x: 0.0, y: 0.0, },
      @scene.Point::{ x: -50.0, y: 50.0, },
      @scene.Point::{ x: 50.0, y: -50.0, },
    ] {
    let world = matrix.point(point)
    let composed = parent
      .local_matrix()
      .point(child.local_matrix().point(point))
    let restored = inverse.point(world)
    let rebased = decomposed.point(point)
    near(world.x, composed.x)
    near(world.y, composed.y)
    near(restored.x, point.x)
    near(restored.y, point.y)
    near(rebased.x, world.x)
    near(rebased.y, world.y)
  }
}

///|
test "singular transforms reject inverse and retain finite collapsed child geometry" {
  let state = {
    ..@scene.default_state(Rectangle),
    scaleX: Some(0.0),
    scaleY: Some(2.0),
    rotation: 49.0,
  }
  let matrix = state.local_matrix()
  assert_true(matrix.inverse() is None)
  let rebased = state.with_matrix(matrix).local_matrix()
  near(matrix.c, rebased.c)
  near(matrix.d, rebased.d)
}

///|
test "concurrent hierarchy cycles have a stable nonrecursive resolution" {
  let objects = [
    object("b", Some("c")),
    object("c", Some("a")),
    object("a", Some("b")),
    object("d", Some("missing")),
  ]
  let first = @scene.prepare_hierarchy(objects)
  let reversed = @scene.prepare_hierarchy([
    objects[3],
    objects[2],
    objects[1],
    objects[0],
  ])
  assert_eq(first.parents, reversed.parents)
  assert_true(!first.parents.contains("a"))
  assert_true(!first.parents.contains("d"))
  let state = { ..@scene.default_state(Rectangle), x: 10.0, y: 0.0, }
  let matrices = first.matrices({
    "a": state,
    "b": state,
    "c": state,
    "d": state,
  })
  near(matrices["a"].e, 10.0)
  near(matrices["c"].e, 20.0)
  near(matrices["b"].e, 30.0)
}

///|
test "reusable layout owns its order and evaluates each current pose" {
  let ordered = [object("child", Some("parent")), object("parent", None)]
  let layout = @scene.ObjectLayout::new(ordered)
  ordered[0] = object("unrelated", None)
  ordered.clear()
  let state = { ..@scene.default_state(Rectangle), x: 10.0, y: 0.0, }
  let first = {
    ..@scene.empty_composition("a", "A", 1000.0, "#ffffff"),
    states: { "parent": { ..state, visible: false, }, "child": state },
  }
  let earlier = layout.evaluate(first, 0.0)
  assert_eq(earlier.length(), 1)
  assert_eq(earlier[0].object.id, "child")
  near(earlier[0].world.unwrap().e, 20.0)
  first.states["parent"] = { ..state, x: 100.0, }
  let latest = layout.evaluate(first, 0.0)
  assert_eq(latest.length(), 2)
  near(latest[0].world.unwrap().e, 110.0)
  near(earlier[0].world.unwrap().e, 20.0)
}

///|
test "indexed composition poses agree with ID hierarchy through cycles and missing or hidden ancestors" {
  let objects = [
    object("leaf", Some("middle")),
    object("z", Some("a")),
    object("middle", Some("root")),
    object("orphan", Some("missing")),
    object("a", Some("z")),
    object("root", None),
  ]
  let layout = @scene.ObjectLayout::new(objects)
  let hierarchy = @scene.prepare_hierarchy(objects)
  for step in 0..<6 {
    let states : Map[String, @scene.ObjectState] = Map([])
    for index, object in objects {
      if object.id == "middle" && step % 2 == 0 {
        continue
      }
      states[object.id] = {
        ..@scene.default_state(Rectangle),
        x: (step * 17 + index * 7).to_double(),
        y: (step - index * 5).to_double(),
        rotation: (step * 11 - index * 8).to_double(),
        scaleX: Some(-0.5),
        scaleY: Some(1.5),
        shear: Some(0.3),
        anchorY: Some(23.0),
        visible: index != step,
      }
    }
    let composition = {
      ..@scene.empty_composition("c", "C", 1000.0, "#ffffff"),
      states,
    }
    let expected = hierarchy.matrices(states)
    let actual = layout.evaluate(composition, 0.0)
    let visible = objects.filter(fn(object) {
      states.get(object.id) is Some(state) && state.visible
    })
    assert_eq(actual.length(), visible.length())
    for index, item in actual {
      assert_eq(item.object.id, visible[index].id)
      assert_eq(item.world, Some(expected[item.object.id]))
      assert_true(item.state == states[item.object.id])
    }
  }
}

///|
test "prepared scene shares structure while keeping each visible and retained pose independent" {
  let parent = {
    ..@scene.default_state(Rectangle),
    x: 10.0,
    y: 20.0,
    rotation: 90.0,
    visible: false,
  }
  let child = { ..@scene.default_state(Rectangle), x: 5.0, y: 0.0, }
  let first = {
    ..@scene.empty_composition("first", "First", 1000.0, "#ffffff"),
    states: { "parent": parent, "child": child },
  }
  let last = {
    ..@scene.empty_composition("last", "Last", 1000.0, "#ffffff"),
    states: {
      "parent": {
        ..parent,
        x: 100.0,
        y: 40.0,
        rotation: 0.0,
        scaleX: Some(2.0),
      },
      "child": { ..child, x: 15.0, },
    },
  }
  let retained = { ..first, id: "retained", deleted: Some(true), }
  let scene = {
    ..@scene.blank_scene("scene", "Scene"),
    objects: {
      "child": object("child", Some("parent")),
      "parent": object("parent", None),
    },
    compositions: { "first": first, "last": last, "retained": retained },
    compositionOrder: ["first", "last"],
    transitions: {
      "change": @scene.Transition::{
        id: "change",
        fromId: "first",
        toId: "last",
        duration: 1000.0,
        tracks: {
          "parent": {
            ..@scene.default_track("parent", 1000.0),
            easing: Linear,
          },
          "child": {
            ..@scene.default_track("child", 1000.0),
            easing: Linear,
            keyframes: Some({
              "point": {
                property: PositionX,
                at: 0.5,
                value: CurveNumber(13.0),
                easing: Linear,
                deleted: None,
              },
            }),
          },
        },
      },
    },
  }
  let authored = scene.to_json()
  let prepared = @scene.prepare_scene(scene, kernel())
  assert_eq(scene.to_json(), authored)
  let earlier = prepared.composition("first", None)
  for time in [0.0, 1000.0, 1250.0, 1500.0, 1750.0, 2000.0, 3000.0] {
    assert_eq(
      prepared.evaluate(time).to_json(),
      @scene.evaluate_scene(scene, time, kernel()).to_json(),
    )
  }
  let last_matrix = prepared.composition("last", None).objects[0].world.unwrap()
  near(last_matrix.e, 130.0)
  near(last_matrix.f, 40.0)
  let initial = earlier.objects[0].world.unwrap()
  near(initial.e, 10.0)
  near(initial.f, 25.0)
  assert_eq(
    prepared.composition("retained", None).objects[0].world,
    Some(initial),
  )
  assert_eq(prepared.composition("first", None).to_json(), earlier.to_json())
}

///|
test "prepared hierarchy preserves paint order through cycles and ancestors without endpoint states" {
  let pose = { ..@scene.default_state(Rectangle), x: 10.0, y: 0.0, }
  let first = {
    ..@scene.empty_composition("a", "A", 1000.0, "#ffffff"),
    states: {
      "a": pose,
      "b": { ..pose, x: 20.0, visible: false, },
      "d": { ..pose, x: 30.0, },
    },
  }
  let last = {
    ..@scene.empty_composition("b", "B", 1000.0, "#ffffff"),
    states: {
      "a": { ..pose, x: 100.0, },
      "b": first.states["b"],
      "d": { ..pose, x: 50.0, },
    },
  }
  let scene = {
    ..@scene.blank_scene("s", "S"),
    objects: {
      "a": { ..object("a", Some("b")), order: 2.0, },
      "b": { ..object("b", Some("a")), order: 1.0, },
      "c": { ..object("c", Some("b")), order: 3.0, },
      "d": object("d", Some("c")),
    },
    compositions: { "a": first, "b": last },
    compositionOrder: ["a", "b"],
    transitions: {
      "t": {
        ..@scene.implicit_transition("t", "a", "b", 1000.0, ["a", "b", "c", "d"]),
        tracks: {
          "a": { ..@scene.default_track("a", 1000.0), easing: Linear, },
          "b": { ..@scene.default_track("b", 1000.0), easing: Linear, },
          "d": { ..@scene.default_track("d", 1000.0), easing: Linear, },
        },
      },
    },
  }
  let program = @scene.prepare_scene(scene, kernel())
  let frame = program.transition("t", 500.0, None)
  assert_eq(frame.objects.map(fn(item) { item.object.id }), ["d", "a"])
  near(frame.objects[0].world.unwrap().e, 115.0)
  near(frame.objects[1].world.unwrap().e, 55.0)
  near(program.composition("a", None).objects[0].world.unwrap().e, 60.0)
  near(program.composition("b", None).objects[0].world.unwrap().e, 170.0)
  // World transforms stay runtime-only; preparation does not repair authored cycles.
  assert_eq(scene.objects["a"].parentId, Some("b"))
  assert_true(!first.states.contains("c"))
}

///|
test "intermediate values allow an out and back motion with linked endpoints and proportional timing" {
  let track = {
    ..@scene.default_track("a", 1000.0),
    easing: Linear,
    positionTiming: Some({ start: 200.0, duration: 600.0, easing: Linear, }),
    keyframes: Some({
      "middle": {
        property: PositionX,
        at: 0.5,
        value: CurveNumber(300.0),
        easing: Linear,
        deleted: None,
      },
    }),
  }
  let curve = @scene.prepare_curve(
    track,
    PositionX,
    CurveNumber(100.0),
    CurveNumber(100.0),
  ).unwrap()
  for
    (time, expected) in [
      (0.0, 100.0),
      (200.0, 100.0),
      (350.0, 200.0),
      (500.0, 300.0),
      (800.0, 100.0),
      (1200.0, 100.0),
    ] {
    assert_true(curve.evaluate(time, kernel()) == @scene.CurveNumber(expected))
  }
  let stretched = @scene.prepare_curve(
    {
      ..track,
      positionTiming: Some({ start: 200.0, duration: 1200.0, easing: Linear, }),
    },
    PositionX,
    CurveNumber(0.0),
    CurveNumber(200.0),
  ).unwrap()
  assert_true(stretched.evaluate(800.0, kernel()) == @scene.CurveNumber(300.0))
  assert_true(stretched.evaluate(1400.0, kernel()) == @scene.CurveNumber(200.0))
}

///|
test "equal-time keys converge and tombstoned keys do not affect interpolation" {
  let first : @scene.Keyframe = {
    property: PositionX,
    at: 0.5,
    value: CurveNumber(10.0),
    easing: EaseIn,
    deleted: None,
  }
  let last = {
    ..first,
    value: @scene.CurveNumber(20.0),
    easing: @scene.Linear,
  }
  let track = {
    ..@scene.default_track("a", 1000.0),
    keyframes: Some({
      "a": first,
      "z": last,
      "ignored": {
        ..last,
        at: 0.75,
        value: CurveNumber(900.0),
        deleted: Some(true),
      },
    }),
  }
  let curve = @scene.prepare_curve(
    track,
    PositionX,
    CurveNumber(0.0),
    CurveNumber(0.0),
  ).unwrap()
  assert_true(curve.evaluate(500.0, kernel()) == @scene.CurveNumber(20.0))
  assert_true(curve.evaluate(750.0, kernel()) == @scene.CurveNumber(10.0))
}

///|
test "single-property and grouped curve preparation retain endpoint semantics and key selection" {
  let key : @scene.Keyframe = {
    property: ObjectWidth,
    at: 0.5,
    value: CurveNumber(200.0),
    easing: Linear,
    deleted: None,
  }
  let track = {
    ..@scene.default_track("a", 1000.0),
    type_: Grow,
    easing: Linear,
    keyframes: Some({
      "a": key,
      "z": { ..key, value: CurveNumber(300.0), },
      "zz": { ..key, value: CurveColor("#ffffff"), },
      "deleted": { ..key, value: CurveNumber(999.0), deleted: Some(true), },
      "alpha": { ..key, property: ObjectOpacity, value: CurveNumber(0.6), },
      "reveal": { ..key, property: ObjectReveal, value: CurveNumber(0.7), },
    }),
  }
  let a = { ..@scene.default_state(Rectangle), width: 100.0, opacity: 0.25, }
  let b = { ..a, width: 200.0, opacity: 0.75, }
  let curves = @scene.prepare_object_curves(track, a, b, false, true)
  assert_true(
    curves.map(fn(curve) { curve.property }) ==
    [@scene.ObjectOpacity, @scene.ObjectWidth, @scene.ObjectReveal],
  )
  for curve in curves {
    let single = @scene.prepare_object_curve(
      track,
      curve.property,
      a,
      b,
      false,
      true,
    ).unwrap()
    for time in [0.0, 250.0, 500.0, 750.0, 1000.0] {
      assert_true(
        single.evaluate(time, kernel()) == curve.evaluate(time, kernel()),
      )
    }
  }
  assert_true(curves[0].evaluate(250.0, kernel()) == @scene.CurveNumber(0.3))
  assert_true(curves[1].evaluate(250.0, kernel()) == @scene.CurveNumber(150.0))
  assert_true(curves[1].evaluate(1000.0, kernel()) == @scene.CurveNumber(200.0))
  assert_true(curves[2].evaluate(500.0, kernel()) == @scene.CurveNumber(0.7))
  assert_true(
    @scene.prepare_object_curve(
      { ..track, type_: Cut, },
      ObjectWidth,
      a,
      b,
      false,
      true,
    )
    is None,
  )
  assert_true(
    @scene.prepare_object_curves({ ..track, type_: Cut, }, a, b, false, true).is_empty(),
  )
}

///|
test "colour curves use the same prepared colour interpolation as the frame evaluator" {
  let track = {
    ..@scene.default_track("a", 1000.0),
    easing: Linear,
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
  let curve = @scene.prepare_curve(
    track,
    ObjectFill,
    CurveColor("#000000"),
    CurveColor("#000000"),
  ).unwrap()
  assert_true(curve.evaluate(250.0, kernel()) == @scene.CurveColor("#808080"))
  assert_true(
    !@scene.valid_keyframe({
      property: ObjectOpacity,
      at: 0.5,
      value: CurveNumber(2.0),
      easing: Linear,
      deleted: None,
    }),
  )
}

///|
test "raster magnification follows scale and shear but ignores screen rotation" {
  let state = {
    ..@scene.default_state(Rectangle),
    scaleX: Some(3.0),
    scaleY: Some(0.5),
    rotation: 79.0,
  }
  near(state.local_matrix().max_scale(), 3.0)
  let matrix : @scene.Affine = {
    a: 1.0,
    b: 0.0,
    c: 2.0,
    d: 1.0,
    e: 0.0,
    f: 0.0,
  }
  assert_true(matrix.max_scale() > 2.4)
  for i = 0; i < 100; i = i + 1 {
    let vector = matrix.vector({
      x: @math.cos(i.to_double()),
      y: @math.sin(i.to_double()),
    })
    assert_true(@math.hypot(vector.x, vector.y) <= matrix.max_scale() + 1.0e-8)
  }
}
