///|
test "Scene selection keeps zero holds at the end while project cuts skip them" {
  let segments : Array[@scene.Segment] = [
    { kind: CompositionSegment, id: "first", start: 0.0, duration: 0.0, },
    { kind: TransitionSegment, id: "move", start: 0.0, duration: 20.0, },
    { kind: CompositionSegment, id: "last", start: 20.0, duration: 0.0, },
  ]
  let selected = fn(time) { @scene.segment_at(segments, time).unwrap().id }
  assert_eq(selected(-1.0), "first")
  assert_eq(selected(0.0), "move")
  assert_eq(selected(19.99), "move")
  assert_eq(selected(20.0), "last")
  assert_eq(selected(100.0), "last")
  assert_true(@scene.segment_at([], 0.0) is None)
  assert_eq(@scene.segment_at([segments[2]], 0.0).unwrap().id, "last")
  let bounds = segments.map(fn(segment) { (segment.start, segment.duration) })
  assert_eq(@scene.project_segment_at(bounds, 0.0), Some(1))
  assert_eq(@scene.project_segment_at(bounds, 20.0), Some(1))
  assert_eq(@scene.project_segment_at([(0.0, 0.0), (0.0, 0.0)], 0.0), Some(0))
  assert_eq(@scene.project_segment_at([], 0.0), None)
}
