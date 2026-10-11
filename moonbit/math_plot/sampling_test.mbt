///|
fn viewport() -> Viewport {
  {
    x_min: -3.0,
    x_max: 3.0,
    y_min: -4.0,
    y_max: 4.0,
    width: 600.0,
    height: 400.0,
  }
}

///|
fn bounded(plot : Plot, viewport : Viewport) -> Unit raise {
  assert_true(plot.evaluations <= 16384)
  assert_true(plot.segments.length() <= 4096)
  for segment in plot.segments {
    for (x, y) in [(segment.x0, segment.y0), (segment.x1, segment.y1)] {
      assert_true(!x.is_nan() && !x.is_inf() && !y.is_nan() && !y.is_inf())
      assert_true(x.abs() <= viewport.width / 2.0 + 1.0e-7)
      assert_true(y.abs() <= viewport.height / 2.0 + 1.0e-7)
    }
  }
}

///|
test "cubic sampling is clipped and accurately follows visible analytic values" {
  let viewport = viewport()
  let result = plot(prepare("x^3-3x"), viewport, 0.0, 0.0, 0.0, [])
  bounded(result, viewport)
  assert_true(!result.limited)
  assert_true(result.segments.length() > 0)
  for segment in result.segments {
    let x = ((segment.x0 + segment.x1) / 2.0 / viewport.width + 0.5) * 6.0 - 3.0
    let y = viewport.point(x, x * x * x - 3.0 * x).1
    // A clipped edge can shorten a chord, but it still follows the curve.
    assert_true((y - (segment.y0 + segment.y1) / 2.0).abs() < 0.6)
  }
  let origin = viewport.point(0.0, 0.0)
  close(origin.0, 0.0)
  close(origin.1, 0.0)
  close(viewport.point(-3.0, 4.0).1, -200.0)
}

///|
test "a pole between sample coordinates keeps both branches and no connecting stroke" {
  let viewport = viewport()
  let result = plot(prepare("1/(x-0.123)"), viewport, 0.0, 0.0, 0.0, [])
  bounded(result, viewport)
  let pole = viewport.point(0.123, 0.0).0
  assert_true(result.segments.any(fn(s) { s.x1 < pole }))
  assert_true(result.segments.any(fn(s) { s.x0 > pole }))
  assert_true(result.segments.all(fn(s) { !(s.x0 < pole && s.x1 > pole) }))
}

///|
test "explicit breaks split finite jumps and duplicate boundaries do not mutate input" {
  let viewport = viewport()
  let breaks = [0.123, 0.123]
  let result = plot(prepare("floor(x-0.123)"), viewport, 0.0, 0.0, 0.0, breaks)
  bounded(result, viewport)
  let at = viewport.point(0.123, 0.0).0
  assert_true(result.segments.all(fn(s) { !(s.x0 < at && s.x1 > at) }))
  assert_eq(breaks, [0.123, 0.123])
}

///|
test "undefined regions, extreme frequencies and invalid viewports have bounded finite output" {
  let viewport = viewport()
  let root = plot(prepare("sqrt(x)"), viewport, 0.0, 0.0, 0.0, [])
  bounded(root, viewport)
  assert_true(root.segments.length() > 0)
  assert_true(root.segments.all(fn(s) { s.x0 >= 0.0 }))
  let oscillation = plot(prepare("sin(100003*x)"), viewport, 0.0, 0.0, 0.0, [])
  bounded(oscillation, viewport)
  assert_true(oscillation.limited)
  for
    bad in [
      { ..viewport, width: 0.0, },
      { ..viewport, x_max: viewport.x_min, },
      { ..viewport, height: 1.0 / 0.0, },
    ] {
    assert_eq(plot(prepare("x"), bad, 0.0, 0.0, 0.0, []).segments.length(), 0)
  }
}

///|
test "chords stay continuous across viewport edges while segments are clipped" {
  let viewport = viewport()
  let above = plot(prepare("5"), viewport, 0.0, 0.0, 0.0, [])
  assert_eq(above.segments, [])
  assert_true(above.chords.length() > 0)
  close(above.chords[0].x0, -300.0)
  close(above.chords[above.chords.length() - 1].x1, 300.0)
  close(above.chords[0].y0, viewport.point(0.0, 5.0).1)
  let cubic = plot(prepare("x^3-3x"), viewport, 0.0, 0.0, 0.0, [])
  assert_true(cubic.chords.any(fn(c) { c.y1.abs() > viewport.height / 2.0 }))
  for index = 1; index < cubic.chords.length(); index = index + 1 {
    assert_eq(
      (cubic.chords[index].x0, cubic.chords[index].y0),
      (cubic.chords[index - 1].x1, cubic.chords[index - 1].y1),
    )
  }
  let pole = plot(prepare("1/x"), viewport, 0.0, 0.0, 0.0, [0.0])
  assert_true(pole.chords.all(fn(c) { !(c.x0 < 0.0 && c.x1 > 0.0) }))
  assert_true(pole.chords.length() <= 4096)
}
