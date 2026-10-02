///|
test "resolution presets and custom edges preserve landscape and portrait ratios" {
  let landscape : Size = { width: 1280.0, height: 720.0, }
  let portrait : Size = { width: 720.0, height: 1280.0, }
  for
    (source, width, height) in [
      (landscape, 3840.0, 2160.0),
      (portrait, 2160.0, 3840.0),
    ] {
    let size = dimensions(source, ShortEdge(2160.0), Mp4)
    assert_eq((size.width, size.height), (width, height))
    assert_true(
      plan("mp4", 30.0, source, Some(size.width), Some(size.height), [200.0])
      is Ok(_),
    )
  }
  let custom = dimensions(landscape, Width(2048.0), Mp4)
  assert_eq((custom.width, custom.height), (2048.0, 1152.0))
  let custom = dimensions(portrait, Height(2560.0), Webm)
  assert_eq((custom.width, custom.height), (1440.0, 2560.0))
  let changed_source = dimensions(
    { width: 1000.0, height: 1000.0, },
    Width(2048.0),
    Mp4,
  )
  assert_eq((changed_source.width, changed_source.height), (2048.0, 2048.0))
}

///|
test "codec rounding stays visible and panoramic presets retain output limits" {
  let odd : Size = { width: 1001.0, height: 751.0, }
  let native = dimensions(odd, Source, Webm)
  let mp4 = dimensions(odd, Source, Mp4)
  assert_eq((native.width, native.height), (1001.0, 751.0))
  assert_eq((mp4.width, mp4.height), (1002.0, 752.0))
  let source : Size = { width: 8192.0, height: 100.0, }
  let size = dimensions(source, ShortEdge(2160.0), Webm)
  assert_true(
    plan("webm", 30.0, source, Some(size.width), Some(size.height), [200.0])
    is Err(_),
  )
}
