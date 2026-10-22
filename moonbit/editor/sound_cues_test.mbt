///|
test "sound cues retain measured alignment through pre-roll trimming" {
  for cue in [0.0, 3.0, 375.5, 980.0] {
    for target in [0.0, 200.25, 1000.0, 600000.0, 86400000.0] {
      guard sound_placement(1000.0, cue, target) is Ok(timing) else {
        fail("playable placement")
      }
      assert_true(
        (timing.start + cue - timing.offset - target).abs() < 0.000001,
      )
      assert_true(timing.start >= 0.0 && timing.offset >= 0.0)
      assert_eq(timing.offset + timing.duration, 1000.0)
    }
  }
  assert_true(sound_placement(1000.0, 1000.0, 0.0) is Err(_))
  assert_true(sound_placement(1000.0, 999.0, 0.0) is Err(_))
  assert_true(sound_placement(1000.0, 1001.0, 100.0) is Err(_))
  assert_true(sound_placement(1000.0, 400.0, -1.0) is Err(_))
  assert_true(sound_placement(1000.0, 400.0, 86400001.0) is Err(_))
  assert_true(sound_placement(1000.0, 400.0, 0.0 / 0.0) is Err(_))
}

///|
test "motion cue ranges include selected track and property timing but stay inside the segment" {
  let segment : @scene.Segment = {
    kind: @scene.TransitionSegment,
    id: "ab",
    start: 1200.0,
    duration: 2000.0,
  }
  let range = sound_cue_range(segment, [])
  assert_eq(range.start, 1200.0)
  assert_eq(range.duration, 2000.0)
  let range = sound_cue_range(segment, [
    { start: 400.0, duration: 900.0, easing: @scene.Linear, },
    { start: 300.0, duration: 200.0, easing: @scene.Linear, },
    { start: 1200.0, duration: 400.0, easing: @scene.Linear, },
  ])
  assert_eq(range.start, 1500.0)
  assert_eq(range.duration, 1300.0)
}

///|
test "audio placement and gain are encoded in the insertion before any identity allocation" {
  let target : ImportScene = {
    width: 1280.0,
    height: 720.0,
    orders: [],
    compositions: ["a"],
    transitions: [],
    start: 0.0,
    audio_count: Some(0),
  }
  let media : @scene.MediaAsset = {
    src: "test",
    mime: "audio/wav",
    duration: 1000.0,
    width: None,
    height: None,
    hasAudio: true,
    waveform: None,
  }
  let allocated = Ref(0)
  let allocate = fn(prefix) {
    allocated.val += 1
    prefix + "\{allocated.val}"
  }
  let options : AudioImport = {
    playback: { start: 0.0, offset: 200.0, duration: 800.0, },
    volume: 0.35,
  }
  guard import_assets(
      target,
      "a",
      [ImportedAudio("Whoosh", media)],
      None,
      allocate,
      audio_options=options,
    )
    is Ok(result) else {
    fail("valid audio")
  }
  assert_eq(result.audio[0].offset, 200.0)
  assert_eq(result.audio[0].duration, 800.0)
  assert_eq(result.audio[0].volume, 0.35)
  allocated.val = 0
  assert_true(
    import_assets(
      target,
      "a",
      [ImportedAudio("Whoosh", media)],
      None,
      allocate,
      audio_options={
        ..options,
        playback: { ..options.playback, duration: 801.0, },
      },
    )
    is Err(_),
  )
  assert_eq(allocated.val, 0)
}
