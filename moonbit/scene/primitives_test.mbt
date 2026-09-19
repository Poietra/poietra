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
