///|
test "atlas allocation bounds reject non-finite and excessive dimensions before narrowing" {
  let item : Drawable = {
    world: None,
    id: "text",
    kind: @scene.Text,
    state: @scene.default_state(@scene.Text),
    progress: 1.0,
    order: Sequential,
    image: None,
    video_frame: None,
  }
  let metrics : TextMetrics = {
    width: 100.0,
    height: 20.0,
    line_height: 25.0,
    baseline: 5.0,
  }
  assert_true(text_atlas_plan(item, metrics, 1.0, 1000000.0) is Some(_))
  for size in [0.0 / 0.0, 1.0 / 0.0, 1.0e30, 2147483648.0] {
    assert_true(
      text_atlas_plan(item, { ..metrics, width: size, }, 1.0, 1000000.0) is None,
    )
  }
  for scale in [0.0, -1.0, 1.0e-320, 1.0e300, 0.0 / 0.0] {
    assert_true(text_atlas_plan(item, metrics, scale, 1000000.0) is None)
  }
  assert_true(text_atlas_plan(item, metrics, 1.0, 1.0) is None)
}
