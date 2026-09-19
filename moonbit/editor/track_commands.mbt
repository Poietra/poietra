///|
/// Invalid host curves stay explicit until validation, rather than decoding to
/// a preset. This also lets a patch repair an invalid stored value.
pub(all) struct TimingCandidate {
  start : Double
  duration : Double
  easing : @scene.Easing?
}

///|
pub(all) enum TrackCommandSource {
  MissingAnimation
  AutomaticAnimation(@scene.Easing?)
  ExplicitAnimation(TimingCandidate)
}

///|
pub(all) enum TrackTimingField {
  SetStart(Double)
  SetDuration(Double)
  SetCurve(@scene.Easing?)
}

///|
pub(all) struct PropertyTimingInput {
  channel : @scene.PropertyChannel
  previous : TimingCandidate?
  next : TimingCandidate?
  changed : Bool
}

///|
pub(all) struct TrackCommandPlan {
  base : @scene.Timing
  create : Bool
  activate : Bool
  fields : Array[TimingField]
  properties : Array[(@scene.PropertyChannel, TimingUpdate)]
}

///|
fn checked_timing(
  timing : TimingCandidate,
  limit : Double,
) -> Result[@scene.Timing, AnimationTimingError] {
  if !@scene.valid_timing_bounds(timing.start, timing.duration, limit) {
    return Err(TimingBounds)
  }
  guard timing.easing is Some(easing) && @scene.valid_easing(easing) else {
    return Err(EasingBounds)
  }
  Ok({ start: timing.start, duration: timing.duration, easing, })
}

///|
/// Activate inherited timing, validate the complete candidate, then plan leaf
/// edits. Missing/automatic tracks keep the single-track API's strict duration:
/// changing only start never silently shortens the inherited duration.
pub fn plan_track_command(
  source : TrackCommandSource,
  patch : Array[TrackTimingField],
  properties : Array[PropertyTimingInput],
  limit : Double,
) -> Result[TrackCommandPlan, AnimationTimingError] {
  let previous : TimingCandidate = match source {
    MissingAnimation =>
      { start: 0.0, duration: limit, easing: Some(EaseInOut), }
    AutomaticAnimation(easing) => { start: 0.0, duration: limit, easing, }
    ExplicitAnimation(timing) => timing
  }
  let mut candidate = previous
  for field in patch {
    candidate = match field {
      SetStart(start) => { ..candidate, start, }
      SetDuration(duration) => { ..candidate, duration, }
      SetCurve(easing) => { ..candidate, easing, }
    }
  }
  let base = match checked_timing(candidate, limit) {
    Err(error) => return Err(error)
    Ok(timing) => timing
  }
  let property_edits = []
  for property in properties {
    let next = match property.next {
      None => None
      Some(candidate) =>
        match checked_timing(candidate, limit) {
          Err(error) => return Err(error)
          Ok(timing) => Some(timing)
        }
    }
    if !property.changed {
      continue
    }
    let update = match (property.previous, next) {
      // The generic track API can explicitly set null or delete an absent field.
      (_, None) => ClearTiming
      (None, Some(timing)) => NewTiming(timing)
      (Some(previous), Some(next)) => {
        let fields = []
        if !number_equal(previous.start, next.start) {
          fields.push(StartTime(next.start))
        }
        if !number_equal(previous.duration, next.duration) {
          fields.push(DurationTime(next.duration))
        }
        if previous.easing != Some(next.easing) {
          fields.push(EasingCurve(next.easing))
        }
        if fields.is_empty() {
          KeepTiming
        } else {
          TimingFields(fields)
        }
      }
    }
    property_edits.push((property.channel, update))
  }
  let activate = source is AutomaticAnimation(_)
  let fields : Array[TimingField] = if activate {
    [StartTime(base.start), DurationTime(base.duration)]
  } else {
    []
  }
  for field in patch {
    match field {
      SetStart(value) =>
        if !activate && !number_equal(previous.start, value) {
          fields.push(StartTime(value))
        }
      SetDuration(value) =>
        if !activate && !number_equal(previous.duration, value) {
          fields.push(DurationTime(value))
        }
      SetCurve(_) =>
        if previous.easing != Some(base.easing) {
          fields.push(EasingCurve(base.easing))
        }
    }
  }
  Ok({
    base,
    create: source is MissingAnimation,
    activate,
    fields,
    properties: property_edits,
  })
}
