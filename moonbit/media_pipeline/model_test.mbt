///|
test "RGBA buffers cannot be confused with dimensions or overflow their byte count" {
  let frame = RgbaFrame(1, 1, b"RGBA")
  assert_eq((frame.width, frame.height, frame.pixels.length()), (1, 1, 4))
  for (width, height) in [(0, 1), (-1, 1), (2, 1), (1073741825, 1)] {
    let invalid = try {
      RgbaFrame(width, height, b"RGBA") |> ignore
      false
    } catch {
      InvalidFrame(_) => true
      _ => false
    }
    assert_true(invalid)
  }
}

///|
test "PCM channels have one sample clock and reject mismatched or invalid input" {
  let left : FixedArray[Float] = [0.0, 0.5]
  let right : FixedArray[Float] = [0.0, -0.5]
  let block = StereoPcm(left, right, 48000, -0.02)
  assert_eq(block.duration(), 2.0 / 48000.0)
  for
    (rate, time, count) in [(0, 0.0, 2), (48000, 0.0 / 0.0, 2), (48000, 0.0, 1)] {
    let invalid = try {
      StereoPcm(left, FixedArray::make(count, 0.0), rate, time) |> ignore
      false
    } catch {
      InvalidAudio(_) => true
      _ => false
    }
    assert_true(invalid)
  }
}
