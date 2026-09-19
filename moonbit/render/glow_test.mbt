///|
test "GPU programs validate limits before allocating and keep pass order explicit" {
  let limits : GraphicsLimits = {
    texture: 1024,
    viewport_width: 800,
    viewport_height: 600,
  }
  let plan = glow_plan(640.0, 480.0, 4.0, limits).unwrap()
  assert_eq(plan.radius, 16)
  assert_eq(plan.passes, [Horizontal, Vertical, Composite(true)])
  assert_eq(glow_plan(640.0, 480.0, 0.0, limits).unwrap().passes, [
    Composite(false),
  ])
  for width in [0.0, -1.0, 16.5, 801.0, 1.0 / 0.0, 0.0 / 0.0] {
    assert_true(glow_plan(width, 20.0, 0.0, limits) is Err(InvalidExtent))
  }
  assert_true(glow_plan(20.0, 601.0, 0.0, limits) is Err(InvalidExtent))
  for sigma in [-1.0, 256.01, 1.0 / 0.0, 0.0 / 0.0] {
    assert_true(glow_plan(20.0, 20.0, sigma, limits) is Err(InvalidRadius))
  }
}
