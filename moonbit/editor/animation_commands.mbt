///|
pub(all) enum TimingField {
  StartTime(Double)
  DurationTime(Double)
  EasingCurve(@scene.Easing)
} derive(Eq)

///|
pub(all) enum TimingUpdate {
  KeepTiming
  ClearTiming
  NewTiming(@scene.Timing)
  TimingFields(Array[TimingField])
}

///|
pub(all) enum AnimationTimingError {
  TransitionBounds
  TimingBounds
  EasingBounds
} derive(Eq, Debug)

///|
pub fn valid_transition_duration(value : Double) -> Bool {
  !value.is_nan() && !value.is_inf() && value >= 0.0 && value <= 120000.0
}

///|
fn timing_fields(
  previous : @scene.Timing,
  next : @scene.Timing,
) -> Array[TimingField] {
  let fields : Array[TimingField] = []
  if !number_equal(previous.start, next.start) {
    fields.push(StartTime(next.start))
  }
  if !number_equal(previous.duration, next.duration) {
    fields.push(DurationTime(next.duration))
  }
  if previous.easing != next.easing {
    fields.push(EasingCurve(next.easing))
  }
  fields
}

///|
/// Existing property timings retain their CRDT parent. Only the changed leaves
/// are written, so an unrelated peer easing/start edit survives a duration edit.
pub fn property_timing_update(
  previous : @scene.Timing?,
  next : @scene.Timing?,
  limit : Double,
) -> Result[TimingUpdate, AnimationTimingError] {
  if next is Some(timing) {
    if !@scene.valid_timing_bounds(timing.start, timing.duration, limit) {
      return Err(TimingBounds)
    }
    if !@scene.valid_easing(timing.easing) {
      return Err(EasingBounds)
    }
  }
  Ok(
    match (previous, next) {
      (None, None) => KeepTiming
      (Some(_), None) => ClearTiming
      (None, Some(timing)) => NewTiming(timing)
      (Some(previous), Some(next)) =>
        if previous.start == next.start &&
          previous.duration == next.duration &&
          previous.easing == next.easing {
          KeepTiming
        } else {
          TimingFields(timing_fields(previous, next))
        }
    },
  )
}

///|
pub(all) struct TrackTimingEdits {
  object_id : String
  channel : @scene.PropertyChannel?
  fields : Array[TimingField]
}

///|
pub(all) struct TransitionResize {
  duration : Double
  tracks : Array[TrackTimingEdits]
}

///|
pub(all) struct TimingRange {
  start : Double
  duration : Double
}

///|
/// Duration edits need numeric bounds, not paths, curves or animation kinds.
/// A missing base denotes an automatic track whose saved base is not a bound.
pub(all) struct TrackTimingInput {
  key : String
  object_id : String
  base : TimingRange?
  properties : Array[(@scene.PropertyChannel, TimingRange)]
}

///|
fn bounded_timing_fields(
  start : Double,
  length : Double,
  limit : Double,
) -> Array[TimingField] {
  let fields : Array[TimingField] = []
  let next_start = start.min(limit)
  let next_length = length.min((limit - start).max(0.0))
  if !number_equal(start, next_start) {
    fields.push(StartTime(next_start))
  }
  if !number_equal(length, next_length) {
    fields.push(DurationTime(next_length))
  }
  fields
}

///|
pub fn resize_transition(
  tracks : Array[TrackTimingInput],
  locked : Set[String],
  requested : Double,
) -> Result[TransitionResize, AnimationTimingError] {
  if !valid_transition_duration(requested) {
    return Err(TransitionBounds)
  }
  let mut duration = requested
  for track in tracks {
    if locked.contains(track.object_id) {
      let mut end = track.base
        .map(fn(timing) { timing.start + timing.duration })
        .unwrap_or(0.0)
      for (_, timing) in track.properties {
        end = @scene.maximum(end, timing.start + timing.duration)
      }
      duration = duration.max(end)
    }
  }
  let edits : Array[TrackTimingEdits] = []
  for track in tracks {
    let id = track.key
    if locked.contains(id) {
      continue
    }
    if track.base is Some(timing) {
      let fields = bounded_timing_fields(
        timing.start,
        timing.duration,
        duration,
      )
      if !fields.is_empty() {
        edits.push({ object_id: id, channel: None, fields, })
      }
    }
    for (channel, timing) in track.properties {
      if timing.start + timing.duration > duration {
        let fields = bounded_timing_fields(
          timing.start,
          timing.duration,
          duration,
        )
        if !fields.is_empty() {
          edits.push({ object_id: id, channel: Some(channel), fields, })
        }
      }
    }
  }
  Ok({ duration, tracks: edits, })
}
