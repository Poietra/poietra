///|
test "raster allocations validate scale, bounds and budget before narrowing" {
  let bounds : Bounds = { x: -10.0, y: -20.0, width: 20.0, height: 40.0, }
  let plan = raster_plan(bounds, 2.0, true).unwrap()
  assert_eq(plan.width, 106)
  assert_eq(plan.height, 146)
  assert_eq(plan.bounds.x, -26.5)
  for scale in [0.0, -1.0, 0.0 / 0.0, 1.0 / 0.0, 1.0e300, 1.0e-320] {
    assert_true(raster_plan(bounds, scale, false) is None)
  }
  assert_true(raster_plan({ ..bounds, width: 0.0 / 0.0, }, 1.0, false) is None)
  assert_true(raster_plan({ ..bounds, width: 1.0e12, }, 1.0, false) is None)
  assert_true(raster_plan({ ..bounds, x: 1.0 / 0.0, }, 1.0, false) is None)
}
