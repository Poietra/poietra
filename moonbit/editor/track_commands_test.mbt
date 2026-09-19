///|
fn explicit_source() -> TrackCommandSource {
  ExplicitAnimation({ start: 100.0, duration: 500.0, easing: Some(Linear), })
}

///|
test "single-track activation inherits the live duration and validates before planning" {
  assert_true(
    plan_track_command(MissingAnimation, [SetStart(100.0)], [], 800.0)
    is Err(TimingBounds),
  )
  guard plan_track_command(
      MissingAnimation,
      [SetStart(100.0), SetDuration(700.0)],
      [],
      800.0,
    )
    is Ok(created) else {
    fail("Expected creation")
  }
  assert_true(created.create && !created.activate)
  assert_eq(created.base.start, 100.0)
  assert_eq(created.base.duration, 700.0)
  guard plan_track_command(
      AutomaticAnimation(Some(EaseOut)),
      [SetDuration(400.0)],
      [],
      1200.0,
    )
    is Ok(activated) else {
    fail("Expected activation")
  }
  assert_true(!activated.create && activated.activate)
  assert_true(activated.fields == [StartTime(0.0), DurationTime(400.0)])
  assert_true(activated.base.easing == EaseOut)
}

///|
test "a repeated curve is a no-op while a changed scalar remains a leaf edit" {
  guard plan_track_command(
      explicit_source(),
      [SetDuration(400.0), SetCurve(Some(Linear))],
      [],
      800.0,
    )
    is Ok(plan) else {
    fail("Expected update")
  }
  assert_true(!plan.create && !plan.activate)
  assert_true(plan.fields == [DurationTime(400.0)])
  assert_eq(plan.properties.length(), 0)
}

///|
test "all property channels retain their timing parents and only change duration" {
  let previous : TimingCandidate = {
    start: 100.0,
    duration: 500.0,
    easing: Some(CubicBezier(0.2, 0.1, 0.7, 0.9)),
  }
  let properties = @scene.property_channels().map(fn(channel) {
    PropertyTimingInput::{
      channel,
      previous: Some(previous),
      next: Some({ ..previous, duration: 400.0, }),
      changed: true,
    }
  })
  guard plan_track_command(explicit_source(), [], properties, 800.0) is Ok(plan) else {
    fail("Expected property edits")
  }
  assert_eq(plan.properties.length(), 11)
  assert_true(plan.fields.is_empty())
  for i, (channel, update) in plan.properties {
    assert_true(channel == @scene.property_channels()[i])
    guard update is TimingFields(fields) else { fail("Expected leaf fields") }
    assert_true(fields == [DurationTime(400.0)])
  }
}

///|
test "new, cleared, unchanged and repaired property timings remain distinct" {
  let previous : TimingCandidate = {
    start: 0.0,
    duration: 500.0,
    easing: Some(Linear),
  }
  let properties : Array[PropertyTimingInput] = [
    { channel: Position, previous: None, next: Some(previous), changed: true, },
    { channel: Opacity, previous: None, next: None, changed: true, },
    {
      channel: Size,
      previous: Some(previous),
      next: Some(previous),
      changed: true,
    },
    {
      channel: Rotation,
      previous: Some({ ..previous, easing: None, }),
      next: Some(previous),
      changed: true,
    },
  ]
  guard plan_track_command(explicit_source(), [], properties, 800.0) is Ok(plan) else {
    fail("Expected property edits")
  }
  assert_true(plan.properties[0].1 is NewTiming(_))
  assert_true(plan.properties[1].1 is ClearTiming)
  assert_true(plan.properties[2].1 is KeepTiming)
  guard plan.properties[3].1 is TimingFields(fields) else {
    fail("Expected repair")
  }
  assert_true(fields == [EasingCurve(Linear)])
}

///|
test "untouched invalid overrides reject the whole candidate in validation order" {
  let invalid : TimingCandidate = {
    start: 700.0,
    duration: 200.0,
    easing: None,
  }
  let properties : Array[PropertyTimingInput] = [
    { channel: Reveal, previous: None, next: Some(invalid), changed: false, },
  ]
  assert_true(
    plan_track_command(
      explicit_source(),
      [SetDuration(400.0)],
      properties,
      800.0,
    )
    is Err(TimingBounds),
  )
  assert_true(
    plan_track_command(explicit_source(), [SetCurve(None)], properties, 800.0)
    is Err(EasingBounds),
  )
  assert_true(
    plan_track_command(
      explicit_source(),
      [SetStart(-1.0), SetCurve(None)],
      properties,
      800.0,
    )
    is Err(TimingBounds),
  )
}

///|
test "signed-zero edits remain observable and zero-duration activation is valid" {
  guard plan_track_command(
      ExplicitAnimation({ start: 0.0, duration: 0.0, easing: Some(Linear), }),
      [SetStart(-0.0)],
      [],
      0.0,
    )
    is Ok(plan) else {
    fail("Expected signed-zero edit")
  }
  guard plan.fields[0] is StartTime(value) else { fail("Expected start") }
  assert_eq(1.0 / value, -1.0 / 0.0)
  guard plan_track_command(AutomaticAnimation(Some(Linear)), [], [], 0.0)
    is Ok(plan) else {
    fail("Expected activation")
  }
  assert_true(plan.activate)
  assert_eq(plan.base.duration, 0.0)
}
