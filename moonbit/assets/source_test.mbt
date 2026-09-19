///|
test "asset references are local immutable paths or supported inert data URLs" {
  let room = "0123456789abcdef"
  let digest = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
  assert_true(valid_source("/api/rooms/\{room}/images/\{digest}", Image))
  assert_true(valid_source("/api/rooms/\{room}/media/\{digest}", Media))
  for
    source in [
      "data:image/png;base64,AQ==", "data:image/jpeg;base64,AQ==", "data:image/webp;base64,AA++//==",
    ] {
    assert_true(valid_source(source, Image))
  }
  for source in ["data:video/mp4;base64,AQ==", "data:audio/wav;base64,AQ=="] {
    assert_true(valid_source(source, Media))
    assert_false(valid_source(source, Image))
  }
  for
    source in [
      "https://example.org/image.png",
      "data:image/svg+xml;base64,AQ==",
      "data:image/png;base64,",
      "data:image/png;base64,AQ===",
      "data:image/png;base64,A=Q",
      "data:image/png;base64,AQ==\n",
      "/api/rooms/short/images/\{digest}",
      "/api/rooms/\{room}/images/../\{digest}",
    ] {
    assert_false(valid_source(source, Image))
  }
  assert_true(valid_image("data:image/png;base64,AQ==", 2048.0, 1.0))
  assert_false(valid_image("data:image/png;base64,AQ==", 2049.0, 1.0))
  assert_false(valid_image("data:image/png;base64,AQ==", 16.5, 1.0))
  assert_eq(video_seconds(5000.0, 2000.0), 1.999999)
  assert_eq(video_seconds(-100.0, 2000.0), 0.0)
}
