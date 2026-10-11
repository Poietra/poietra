///|
test "heightfields and parametric coordinates share bounded two-variable evaluation" {
  let plane = @math_surface.prepare("u", "v", "a*x+b*y+c", true)
  assert_eq(
    plane.point(2.0, 3.0, 4.0, 5.0, 6.0),
    Some({ x: 2.0, y: 3.0, z: 29.0, }),
  )
  let mesh = @math_surface.sample(plane, -2.0, 2.0, -2.0, 2.0, 1.0, 2.0, 3.0, 4)
  assert_eq(mesh.triangles.length(), 32)
  assert_eq(mesh.omitted, 0)
  assert_eq(mesh.evaluations, 123)
  for t in mesh.triangles {
    for p in [t.a, t.b, t.c] {
      assert_true((p.z - p.x - 2.0 * p.y - 3.0).abs() < 1.0e-9)
    }
  }
  let parametric = @math_surface.prepare("a*cos(u)", "a*sin(u)", "v", false)
  let p = parametric.point(0.0, 3.0, 2.0, 0.0, 0.0).unwrap()
  assert_eq(p, { x: 2.0, y: 0.0, z: 3.0, })
}

///|
test "orthographic rotation preserves depth and independent coordinate axes" {
  let p = @math_surface.project({ x: 2.0, y: 3.0, z: 4.0, }, 0.0, 0.0)
  assert_eq(p, { x: 2.0, y: -4.0, depth: -3.0, })
  let rotated = @math_surface.project({ x: 2.0, y: 3.0, z: 4.0, }, 90.0, 90.0)
  assert_true((rotated.x + 3.0).abs() < 1.0e-9)
  assert_true((rotated.y + 2.0).abs() < 1.0e-9)
  assert_true((rotated.depth - 4.0).abs() < 1.0e-9)
}

///|
test "undefined and pole-spanning cells are omitted without bridging discontinuities" {
  let pole = @math_surface.prepare("u", "v", "1/x", true)
  assert_true(pole.point(0.0, 0.0, 0.0, 0.0, 0.0) is None)
  let mesh = @math_surface.sample(pole, -1.0, 1.0, -1.0, 1.0, 0.0, 0.0, 0.0, 5)
  assert_true(mesh.omitted >= 5)
  for t in mesh.triangles {
    assert_true(
      (t.a.x < 0.0 && t.b.x < 0.0 && t.c.x < 0.0) ||
      (t.a.x > 0.0 && t.b.x > 0.0 && t.c.x > 0.0),
    )
  }
  let outside = @math_surface.prepare("u", "v", "sqrt(x)", true)
  assert_true(
    @math_surface.sample(outside, -2.0, -1.0, -1.0, 1.0, 0.0, 0.0, 0.0, 8).triangles.is_empty(),
  )
}

///|
test "grid work has a fixed bound and invalid subdivision counts do no work" {
  let plane = @math_surface.prepare("u", "v", "0", true)
  let mesh = @math_surface.sample(
    plane, -1.0, 1.0, -1.0, 1.0, 0.0, 0.0, 0.0, 48,
  )
  assert_eq(mesh.evaluations, 14115)
  assert_eq(mesh.triangles.length(), 4608)
  for steps in [0, 3, 49, 1000000] {
    let mesh = @math_surface.sample(
      plane, -1.0, 1.0, -1.0, 1.0, 0.0, 0.0, 0.0, steps,
    )
    assert_eq(mesh.evaluations, 0)
    assert_true(mesh.triangles.is_empty())
  }
}
