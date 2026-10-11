///|
test "evaluates a dependency chain independently of input order and omits cycles and missing references" {
  let result = evaluate([
    { id: "n", construction: Midpoint("m", "b"), },
    { id: "m", construction: Midpoint("a", "b"), },
    { id: "a", construction: Free({ x: -2.0, y: 0.0, }), },
    { id: "b", construction: Free({ x: 2.0, y: 4.0, }), },
    { id: "cycle", construction: Midpoint("cycle", "a"), },
    { id: "missing", construction: Midpoint("absent", "a"), },
  ])
  assert_eq(result.points["m"], { x: 0.0, y: 2.0, })
  assert_eq(result.points["n"], { x: 1.0, y: 3.0, })
  assert_eq(result.unresolved, ["cycle", "missing"])
}

///|
test "midpoints avoid overflow and degenerate angle arms are explicit" {
  let result = evaluate([
    { id: "a", construction: Free({ x: 1.0e308, y: -1.0e308, }), },
    { id: "m", construction: Midpoint("a", "a"), },
  ])
  assert_eq(result.points["m"], result.points["a"])
  let origin : Point = { x: 0.0, y: 0.0, }
  assert_eq(angle({ x: 1.0, y: 0.0, }, origin, { x: 0.0, y: 1.0, }), Some(90.0))
  assert_eq(angle(origin, origin, { x: 1.0, y: 0.0, }), None)
  assert_eq(length(vector(origin, { x: 3.0, y: 4.0, })), 5.0)
}
