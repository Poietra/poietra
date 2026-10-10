///|
fn contour_viewport() -> Viewport {
  {
    x_min: -2.0,
    x_max: 2.0,
    y_min: -2.0,
    y_max: 2.0,
    width: 400.0,
    height: 400.0,
  }
}

///|
fn bounded_contour(plot : Plot, viewport : Viewport) -> Unit raise {
  assert_true(plot.evaluations <= 65536)
  assert_true(plot.segments.length() <= 8192)
  for segment in plot.segments {
    for (x, y) in [(segment.x0, segment.y0), (segment.x1, segment.y1)] {
      assert_true(!x.is_nan() && !x.is_inf() && !y.is_nan() && !y.is_inf())
      assert_true(x.abs() <= viewport.width / 2.0 + 1.0e-7)
      assert_true(y.abs() <= viewport.height / 2.0 + 1.0e-7)
    }
  }
}

///|
test "circle contours are accurate, closed and connected for continuous Write" {
  let viewport = contour_viewport()
  for source in ["x^2+y^2=a^2", "(x^2+y^2)*1e-20=a^2*1e-20"] {
    let plot = plot_implicit(
      prepare_implicit(source),
      viewport,
      1.0,
      0.0,
      0.0,
      [],
    )
    bounded_contour(plot, viewport)
    assert_true(!plot.limited)
    assert_true(plot.segments.length() > 100)
    for segment in plot.segments {
      assert_true((@math.hypot(segment.x0, segment.y0) - 100.0).abs() < 0.001)
      assert_true(
        (@math.hypot(
          (segment.x0 + segment.x1) / 2.0,
          (segment.y0 + segment.y1) / 2.0,
        ) -
        100.0).abs() <
        0.1,
      )
    }
    for index = 0; index < plot.segments.length(); index = index + 1 {
      let a = plot.segments[index]
      let b = plot.segments[(index + 1) % plot.segments.length()]
      assert_eq((a.x1, a.y1), (b.x0, b.y0))
    }
  }
}

///|
test "disconnected hyperbola branches and exact saddles retain their topology" {
  let viewport = contour_viewport()
  let hyperbola = plot_implicit(
    prepare_implicit("x*y=1"),
    viewport,
    0.0,
    0.0,
    0.0,
    [],
  )
  bounded_contour(hyperbola, viewport)
  assert_true(!hyperbola.limited)
  assert_true(hyperbola.segments.any(fn(s) { s.x0 > 0.0 && s.y0 < 0.0 }))
  assert_true(hyperbola.segments.any(fn(s) { s.x0 < 0.0 && s.y0 > 0.0 }))
  assert_true(
    hyperbola.segments.all(fn(s) { s.x0 * s.x1 > 0.0 && s.y0 * s.y1 > 0.0 }),
  )
  let saddle = plot_implicit(
    prepare_implicit("x*y=0"),
    viewport,
    0.0,
    0.0,
    0.0,
    [],
  )
  bounded_contour(saddle, viewport)
  assert_true(!saddle.limited)
  assert_true(saddle.segments.any(fn(s) { s.x0 == -200.0 }))
  assert_true(saddle.segments.any(fn(s) { s.x1 == 200.0 }))
  assert_true(saddle.segments.any(fn(s) { s.y0 == 200.0 }))
  assert_true(saddle.segments.any(fn(s) { s.y1 == -200.0 }))
  assert_true(
    saddle.segments.all(fn(s) {
      (s.x0 == 0.0 && s.x1 == 0.0) || (s.y0 == 0.0 && s.y1 == 0.0)
    }),
  )
}

///|
test "an elliptic curve keeps its closed oval separate from the unbounded branch" {
  let viewport = contour_viewport()
  let plot = plot_implicit(
    prepare_implicit("y^2=x^3-x"),
    viewport,
    0.0,
    0.0,
    0.0,
    [],
  )
  bounded_contour(plot, viewport)
  assert_true(!plot.limited)
  assert_true(plot.segments.any(fn(s) { s.x0 < 0.0 }))
  assert_true(plot.segments.any(fn(s) { s.x0 > 100.0 && s.y0 < 0.0 }))
  assert_true(plot.segments.any(fn(s) { s.x0 > 100.0 && s.y0 > 0.0 }))
  for segment in plot.segments {
    assert_true(
      (segment.x0 <= 0.00001 && segment.x1 <= 0.00001) ||
      (segment.x0 >= 99.99999 && segment.x1 >= 99.99999),
    )
    for
      (x, y) in [
        (segment.x0 / 100.0, -segment.y0 / 100.0),
        (segment.x1 / 100.0, -segment.y1 / 100.0),
      ] {
      assert_true((y * y - x * x * x + x).abs() < 0.00001)
    }
  }
}

///|
test "cell centers reveal a small closed component and grid-aligned repeated roots" {
  let viewport : Viewport = {
    x_min: -1.0,
    x_max: 1.0,
    y_min: -1.0,
    y_max: 1.0,
    width: 64.0,
    height: 64.0,
  }
  let small = plot_implicit(
    prepare_implicit("(x-0.0625)^2+(y-0.0625)^2=0.0009"),
    viewport,
    0.0,
    0.0,
    0.0,
    [],
  )
  bounded_contour(small, viewport)
  assert_true(!small.limited)
  assert_true(small.segments.length() >= 4)
  let line = plot_implicit(prepare_implicit("x^2=0"), viewport, 0.0, 0.0, 0.0, [])
  assert_true(!line.limited)
  assert_true(line.segments.length() > 0)
  assert_true(line.segments.all(fn(s) { s.x0 == 0.0 && s.x1 == 0.0 }))
}

///|
test "poles, finite jumps and undefined regions cannot masquerade as equation roots" {
  let viewport = contour_viewport()
  for source in ["1/(x-0.123)=0", "floor(x-0.123)+0.5=0", "sqrt(-1)=y"] {
    let plot = plot_implicit(
      prepare_implicit(source),
      viewport,
      0.0,
      0.0,
      0.0,
      [],
    )
    bounded_contour(plot, viewport)
    assert_eq(plot.segments.length(), 0)
  }
  let root = plot_implicit(
    prepare_implicit("sqrt(x)=y"),
    viewport,
    0.0,
    0.0,
    0.0,
    [],
  )
  bounded_contour(root, viewport)
  assert_true(root.segments.length() > 0)
  assert_true(
    root.segments.all(fn(s) {
      s.x0 >= 0.0 && s.x1 >= 0.0 && s.y0 <= 0.0 && s.y1 <= 0.0
    }),
  )
}

///|
test "implicit work caps, empty sets, zero-valued areas and breaks remain bounded" {
  let viewport = contour_viewport()
  for source in ["sin(10003*x)*cos(10007*y)=0", "1=1"] {
    let plot = plot_implicit(
      prepare_implicit(source),
      viewport,
      0.0,
      0.0,
      0.0,
      [],
    )
    bounded_contour(plot, viewport)
    assert_true(plot.limited)
  }
  let empty = plot_implicit(
    prepare_implicit("x^2+y^2=-1"),
    viewport,
    0.0,
    0.0,
    0.0,
    [],
  )
  assert_eq(empty.segments.length(), 0)
  assert_true(!empty.limited)
  let breaks = [0.0]
  let split = plot_implicit(
    prepare_implicit("x^2+y^2=1"),
    viewport,
    0.0,
    0.0,
    0.0,
    breaks,
  )
  bounded_contour(split, viewport)
  assert_true(
    split.segments.all(fn(s) {
      (s.x0 < 0.0 && s.x1 < 0.0) || (s.x0 > 0.0 && s.x1 > 0.0)
    }),
  )
  assert_eq(breaks, [0.0])
  for
    bad in [
      { ..viewport, width: 0.0, },
      { ..viewport, x_max: viewport.x_min, },
      { ..viewport, height: 1.0 / 0.0, },
    ] {
    assert_eq(
      plot_implicit(prepare_implicit("x+y=0"), bad, 0.0, 0.0, 0.0, []).segments.length(),
      0,
    )
  }
}
