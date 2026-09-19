///|
test "clock subtraction matches point-set subtraction for arbitrary overlaps" {
  let mut random = 7187U
  fn draw() -> Int {
    random = random * 1664525U + 1013904223U
    (random % 80U).reinterpret_as_int()
  }
  for _ in 0..<500 {
    let source = Array::makei(12, fn(_) {
      ClockSpan::{
        clock: draw().to_double(),
        length: (draw() % 20).to_double(),
      }
    })
    let cuts = Array::makei(15, fn(_) {
      ClockSpan::{
        clock: draw().to_double(),
        length: (draw() % 20).to_double(),
      }
    })
    let before = source.copy()
    let result = omit_clock_spans(source, cuts)
    assert_eq(source, before)
    for point in 0..<100 {
      let point = point.to_double()
      let contains = fn(spans : Array[ClockSpan]) {
        spans
        .iter()
        .any(fn(span) {
          span.clock <= point && point < span.clock + span.length
        })
      }
      assert_eq(contains(result), contains(source) && !contains(cuts))
    }
    for i in 1..<result.length() {
      assert_true(result[i - 1].clock + result[i - 1].length < result[i].clock)
    }
  }
}

///|
test "clock subtraction retains safe integer positions beyond 32 bits" {
  assert_eq(
    omit_clock_spans([{ clock: 4294967296.0, length: 10.0, }], [
      { clock: 4294967299.0, length: 3.0, },
    ]),
    [
      { clock: 4294967296.0, length: 3.0, },
      { clock: 4294967302.0, length: 4.0, },
    ],
  )
}
