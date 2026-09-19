///|
pub fn clamp(value : Double, low : Double, high : Double) -> Double {
  let value = if value.is_nan() || value.is_inf() { low } else { value }
  minimum(high, maximum(low, value))
}

///|
/// Preserve invalid-number propagation at saved-document boundaries. MoonBit's
/// Double.max/min deliberately ignore a single NaN, unlike the source contract.
pub fn maximum(a : Double, b : Double) -> Double {
  if a.is_nan() {
    a
  } else if b.is_nan() {
    b
  } else if a == 0.0 && b == 0.0 {
    a + b
  } else {
    a.max(b)
  }
}

///|
pub fn minimum(a : Double, b : Double) -> Double {
  -maximum(-a, -b)
}

///|
pub fn default_track(object_id : String, duration : Double) -> Track {
  {
    implicit: None,
    objectId: object_id,
    type_: Move,
    start: 0.0,
    duration,
    easing: EaseInOut,
    order: "together",
    path: None,
    positionTiming: None,
    opacityTiming: None,
    sizeTiming: None,
    rotationTiming: None,
    fillTiming: None,
    strokeTiming: None,
    strokeWidthTiming: None,
    fontSizeTiming: None,
    cornerRadiusTiming: None,
    pathTiming: None,
    revealTiming: None,
  }
}

///|
pub fn resolve_track(
  track : Track?,
  object_id : String,
  duration : Double,
) -> Track {
  match track {
    None => default_track(object_id, duration)
    Some(track) =>
      if track.implicit == Some(true) {
        { ..track, start: 0.0, duration, }
      } else {
        track
      }
  }
}

///|
pub fn scene_segments(scene : Scene) -> Array[Segment] {
  timeline_segments(scene_timeline(scene))
}

///|
pub fn scene_duration(scene : Scene) -> Double {
  timeline_duration(scene_timeline(scene))
}

///|
pub fn segment_start(scene : Scene, kind : String, id : String) -> Double {
  for segment in scene_segments(scene) {
    if segment.kind == kind && segment.id == id {
      return segment.start
    }
  }
  0.0
}
