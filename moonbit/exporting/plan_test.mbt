///|
test "container duration and derived dimensions are validated before conversion" {
  let size : Size = { width: 1280.0, height: 720.0, }
  let mp4 = plan("mp4", 30.0, size, Some(640.0), None, [45.0]).unwrap()
  let webm = plan("webm", 30.0, size, Some(321.0), Some(181.0), [45.0]).unwrap()
  assert_eq((mp4.width, mp4.height, mp4.frames), (640, 360, 2))
  assert_eq(mp4.duration, 45.0)
  assert_eq(mp4.timestamp(1) + mp4.frame_duration(1), 0.045)
  assert_eq(webm.duration, 2.0 / 30.0 * 1000.0)
  assert_true(
    plan("mp4", 30.0, size, Some(321.0), Some(180.0), [45.0]) is Err(_),
  )
  for width in [0.0, -1.0, 8193.0, 32.5, 0.0 / 0.0, 1.0 / 0.0] {
    assert_true(plan("webm", 30.0, size, Some(width), None, [45.0]) is Err(_))
  }
  for duration in [0.0, -1.0, 0.0 / 0.0, 1.0 / 0.0, 1.0e15] {
    assert_true(plan("webm", 30.0, size, None, None, [duration]) is Err(_))
  }
}
