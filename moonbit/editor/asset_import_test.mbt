///|
test "mixed imports preflight every track before allocating any document identity" {
  let target : ImportScene = {
    width: 1280.0,
    height: 720.0,
    orders: [],
    compositions: ["a", "b"],
    transitions: [("ab", 800.0)],
    start: 2000.0,
    audio_count: Some(100),
  }
  let image : @scene.ImageAsset = { src: "test", width: 80.0, height: 40.0, }
  let media : @scene.MediaAsset = {
    src: "test",
    mime: "audio/wav",
    duration: 3000.0,
    width: None,
    height: None,
    hasAudio: true,
    waveform: None,
  }
  let allocated = Ref(0)
  let id = fn(prefix) {
    allocated.val += 1
    prefix + "\{allocated.val}"
  }
  assert_true(
    import_assets(
      target,
      "b",
      [ImportedImage("Picture", image), ImportedAudio("Audio", media)],
      None,
      id,
    )
    is Err(_),
  )
  assert_eq(allocated.val, 0)
  let result = import_assets(
    { ..target, audio_count: Some(0), },
    "b",
    [ImportedImage("Picture", image), ImportedAudio("Audio", media)],
    None,
    id,
  )
  guard result is Ok(result) else { fail("Expected complete mixed batch") }
  assert_eq(result.objects.length(), 1)
  assert_eq(result.audio.length(), 1)
  assert_eq(result.audio[0].start, 2000.0)
  assert_eq(result.objects[0].states[0].1.visible, false)
  assert_eq(result.objects[0].states[1].1.visible, true)
  assert_eq(result.objects[0].states[1].1.x, 640.0)
  assert_eq(result.objects[0].tracks[0].1.implicit, Some(true))
  assert_true(
    import_assets(
      { ..target, orders: Array::make(500, 0.0), },
      "b",
      [ImportedImage("Picture", image)],
      None,
      id,
    )
    is Err(_),
  )
  assert_true(
    import_assets(
      { ..target, audio_count: None, },
      "b",
      [ImportedAudio("Audio", media)],
      None,
      id,
    )
    is Err(_),
  )
}
