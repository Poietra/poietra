///|
/// Regression cases from the pinned original Rust kernel tests.
test "independent track clocks and instantaneous duration" {
  assert_eq(@motion.track_progress(399.0, 400.0, 400.0, 1), 0.0)
  assert_eq(@motion.track_progress(600.0, 400.0, 400.0, 1), 0.5)
  assert_eq(@motion.track_progress(900.0, 400.0, 400.0, 1), 1.0)
  assert_eq(@motion.track_progress(400.0, 400.0, 0.0, 1), 1.0)
}

///|
test "custom easing solves horizontal handles before vertical progress" {
  assert_eq(@motion.cubic_bezier_ease(0.125, 0.0, 0.0, 0.0, 1.0), 0.5)
  assert_eq(@motion.cubic_bezier_ease(0.875, 1.0, 0.0, 1.0, 1.0), 0.5)
}

///|
test "flat tangent easing stays monotone and bounded" {
  for
    (x1, y1, x2, y2) in [
      (0.0, 1.0, 0.0, 1.0),
      (1.0, 0.0, 1.0, 0.0),
      (1.0, 0.0, 0.0, 1.0),
    ] {
    let mut previous = 0.0
    for sample in 0..<=1000 {
      let value = @motion.cubic_bezier_ease(
        sample.to_double() / 1000.0,
        x1,
        y1,
        x2,
        y2,
      )
      assert_true(value >= previous && value <= 1.0)
      previous = value
    }
  }
}
