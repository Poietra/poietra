///|
test "headless uses shared dimensions and accepts long high-frame-count projects" {
  let a = @scene.blank_scene("a", "A")
  a.compositions["a-comp-1"] = {
    ..a.compositions["a-comp-1"],
    duration: 45000.0,
  }
  let b = @scene.blank_scene("b", "B")
  b.compositions["b-comp-1"] = {
    ..b.compositions["b-comp-1"],
    duration: 45000.0,
  }
  let timeline = prepare(
    {
      version: 2,
      name: "Long project",
      sceneOrder: ["a", "b"],
      scenes: { "a": a, "b": b },
    },
    fn(a, b) { a.compare(b) },
  )
  for format in [Mp4, Svg, Png] {
    let request : RenderRequest = {
      format,
      width: Some(3840.0),
      height: Some(2160.0),
      fps: 60.0,
      time_ms: 0.0,
    }
    let plan = validate(timeline, request)
    assert_eq((plan.width, plan.height, plan.frames), (3840, 2160, 5400))
    assert_eq(plan.duration, 90000.0)
    let portrait = validate(timeline, {
      ..request,
      width: Some(2160.0),
      height: Some(3840.0),
    })
    assert_eq((portrait.width, portrait.height), (2160, 3840))
    for
      invalid in [
        { ..request, width: Some(8193.0), },
        { ..request, time_ms: -1.0, },
      ] {
      try validate(timeline, invalid) catch {
        Invalid(_) => ()
        error => raise error
      } noraise {
        _ => fail("Invalid output options were accepted")
      }
    }
  }
}
