///|
test "alignment accounts for renderer bounds relative to object anchors" {
  let items : Array[AlignmentItem] = [
    { id: "text", position: 100.0, low: 80.0, extent: 60.0, },
    { id: "shape", position: 300.0, low: 250.0, extent: 100.0, },
  ]
  assert_eq(alignment_plan(items, 1280.0, AlignStart), [
    ("text", 100.0),
    ("shape", 130.0),
  ])
  assert_eq(alignment_plan(items, 1280.0, AlignCenter), [
    ("text", 205.0),
    ("shape", 215.0),
  ])
  assert_eq(alignment_plan([items[0]], 1280.0, AlignEnd), [("text", 1240.0)])
  assert_eq(color_code("aF1200"), Some("#aF1200"))
  for invalid in ["", "#123", "#1234567", " 123456", "#abcdef\n", "ＦＦ0011"] {
    assert_eq(color_code(invalid), None)
  }
}

///|
test "media trim preserves source and timeline endpoints at both limits" {
  let before : @scene.MediaPlayback = {
    start: 200.0,
    offset: 80.0,
    duration: 1000.0,
  }
  assert_eq(media_gesture(before, TrimStart, -1000.0, 2000.0), {
    start: 120.0,
    offset: 0.0,
    duration: 1080.0,
  })
  assert_eq(media_gesture(before, TrimStart, 2000.0, 2000.0), {
    start: 1190.0,
    offset: 1070.0,
    duration: 10.0,
  })
  assert_eq(media_gesture(before, TrimEnd, 2000.0, 2000.0).duration, 1920.0)
  assert_eq(media_gesture(before, MoveTiming, -1000.0, 2000.0), {
    ..before,
    start: 0.0,
  })
}
