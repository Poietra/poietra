///|
fn timing_input(track : @scene.Track) -> TrackTimingInput {
  let properties = []
  for channel in @scene.property_channels() {
    if @scene.timing_override(track, channel) is Some(timing) {
      properties.push(
        (
          channel,
          TimingRange::{ start: timing.start, duration: timing.duration, },
        ),
      )
    }
  }
  {
    key: track.objectId,
    object_id: track.objectId,
    base: if track.implicit == Some(true) {
      None
    } else {
      Some({ start: track.start, duration: track.duration, })
    },
    properties,
  }
}

///|
test "transition resize emits only changed leaves and no track writes when extending" {
  let track = { ..@scene.default_track("a", 700.0), start: 100.0, }
  guard resize_transition([timing_input(track)], Set([]), 500.0) is Ok(plan) else {
    fail("Expected resize")
  }
  assert_eq(plan.duration, 500.0)
  assert_eq(plan.tracks.length(), 1)
  assert_eq(plan.tracks[0].object_id, "a")
  assert_true(plan.tracks[0].channel is None)
  assert_true(plan.tracks[0].fields == [DurationTime(400.0)])
  guard resize_transition([timing_input(track)], Set([]), 1000.0)
    is Ok(extended) else {
    fail("Expected extension")
  }
  assert_eq(extended.tracks.length(), 0)
  assert_eq(track.start, 100.0)
  assert_eq(track.duration, 700.0)
}

///|
test "every property is clamped without rewriting its easing or the implicit base" {
  let timing : @scene.Timing = {
    start: 100.0,
    duration: 700.0,
    easing: CubicBezier(0.2, 0.1, 0.7, 0.9),
  }
  let mut track = { ..@scene.default_track("a", 800.0), implicit: Some(true), }
  for channel in @scene.property_channels() {
    track = @scene.with_timing_override(track, channel, Some(timing))
  }
  guard resize_transition([timing_input(track)], Set([]), 500.0) is Ok(plan) else {
    fail("Expected resize")
  }
  assert_eq(plan.tracks.length(), 11)
  for index, change in plan.tracks {
    assert_true(change.channel == Some(@scene.property_channels()[index]))
    assert_true(change.fields == [DurationTime(400.0)])
  }
  assert_eq(track.duration, 800.0)
  assert_eq(track.opacityTiming.unwrap().duration, 700.0)
}

///|
test "locked implicit tracks protect their overrides but not their stale base timing" {
  let locked = {
    ..@scene.default_track("locked", 900.0),
    implicit: Some(true),
    positionTiming: Some({ start: 100.0, duration: 500.0, easing: Linear, }),
  }
  let editable = { ..@scene.default_track("free", 700.0), start: 100.0, }
  guard resize_transition(
      [timing_input(locked), timing_input(editable)],
      Set(["locked"]),
      300.0,
    )
    is Ok(plan) else {
    fail("Expected resize")
  }
  assert_eq(plan.duration, 600.0)
  assert_eq(plan.tracks.length(), 1)
  assert_eq(plan.tracks[0].object_id, "free")
  assert_true(plan.tracks[0].fields == [DurationTime(500.0)])
}

///|
test "zero-duration transitions clamp a late start and its duration together" {
  let track = { ..@scene.default_track("a", 300.0), start: 100.0, }
  guard resize_transition([timing_input(track)], Set([]), 0.0) is Ok(plan) else {
    fail("Expected resize")
  }
  assert_true(plan.tracks[0].fields == [StartTime(0.0), DurationTime(0.0)])
  for value in [-1.0, 120001.0, 0.0 / 0.0, 1.0 / 0.0] {
    assert_true(
      resize_transition([timing_input(track)], Set(["a"]), value)
      is Err(TransitionBounds),
    )
  }
}

///|
test "property timing changes are typed insert, clear, no-op or leaf edits" {
  let current : @scene.Timing = {
    start: 10.0,
    duration: 100.0,
    easing: CubicBezier(0.2, 0.1, 0.7, 0.9),
  }
  assert_true(property_timing_update(None, None, 500.0) is Ok(KeepTiming))
  assert_true(
    property_timing_update(Some(current), Some(current), 500.0)
    is Ok(KeepTiming),
  )
  assert_true(
    property_timing_update(None, Some(current), 500.0) is Ok(NewTiming(_)),
  )
  assert_true(
    property_timing_update(Some(current), None, 500.0) is Ok(ClearTiming),
  )
  guard property_timing_update(
      Some(current),
      Some({ ..current, start: 20.0, duration: 80.0, }),
      500.0,
    )
    is Ok(TimingFields(fields)) else {
    fail("Expected leaf edits")
  }
  assert_true(fields == [StartTime(20.0), DurationTime(80.0)])
  assert_true(
    property_timing_update(
      Some(current),
      Some({ ..current, duration: 501.0, }),
      500.0,
    )
    is Err(TimingBounds),
  )
  assert_true(
    property_timing_update(
      Some(current),
      Some({ ..current, easing: CubicBezier(0.2, 0.1, 2.0, 0.9), }),
      500.0,
    )
    is Err(EasingBounds),
  )
}

///|
test "property timing no-op equality retains signed-zero boundary behavior" {
  let current : @scene.Timing = { start: 0.0, duration: 100.0, easing: Linear, }
  assert_true(
    property_timing_update(
      Some(current),
      Some({ ..current, start: -0.0, }),
      500.0,
    )
    is Ok(KeepTiming),
  )
  guard property_timing_update(
      Some(current),
      Some({ ..current, start: -0.0, easing: EaseIn, }),
      500.0,
    )
    is Ok(TimingFields(fields)) else {
    fail("Expected leaf edits")
  }
  guard fields[0] is StartTime(value) else {
    fail("Expected signed-zero update")
  }
  assert_eq(1.0 / value, -1.0 / 0.0)
  assert_true(fields[1] == EasingCurve(EaseIn))
}
