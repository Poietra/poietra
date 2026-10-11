///|
test "degree counts directed and undirected loops and parallel edges separately" {
  let edges : Array[@math_network.Edge] = [
    { from: "a", to: "b", directed: true, },
    { from: "b", to: "a", directed: true, },
    { from: "a", to: "a", directed: true, },
    { from: "a", to: "a", directed: false, },
    { from: "a", to: "b", directed: false, },
    { from: "a", to: "b", directed: false, },
  ]
  assert_eq(@math_network.degree("a", edges), {
    incoming: 2,
    outgoing: 2,
    undirected: 4,
  })
  assert_eq(@math_network.degree("b", edges), {
    incoming: 1,
    outgoing: 1,
    undirected: 2,
  })
  assert_eq(@math_network.degree("missing", edges), {
    incoming: 0,
    outgoing: 0,
    undirected: 0,
  })
}

///|
test "circular layout is independent of map order, preserves inputs and bounds capacity" {
  let ids = ["c", "a", "b", "d"]
  let points = @math_network.circle(ids, 2.0)
  assert_eq(ids, ["c", "a", "b", "d"])
  assert_eq(points.map(fn(p) { p.id }), ["a", "b", "c", "d"])
  for
    (p, x, y) in [
      (points[0], 2.0, 0.0),
      (points[1], 0.0, 2.0),
      (points[2], -2.0, 0.0),
      (points[3], 0.0, -2.0),
    ] {
    assert_true((p.x - x).abs() < 1.0e-9 && (p.y - y).abs() < 1.0e-9)
  }
  assert_eq(@math_network.circle([], 1.0).length(), 0)
  assert_eq(
    @math_network.circle(Array::makei(129, fn(i) { i.to_string() }), 1.0).length(),
    0,
  )
  assert_eq(@math_network.circle(["a"], 1.0 / 0.0).length(), 0)
}
