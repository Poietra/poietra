///|
pub fn clamp(value : Double, low : Double, high : Double) -> Double {
  let value = if value.is_nan() || value.is_inf() { low } else { value }
  value.max(low).min(high)
}

///|
pub fn default_track(object_id : String, duration : Double) -> Track {
  {
    implicit: None,
    objectId: object_id,
    type_: "move",
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
  let segments : Array[Segment] = []
  let mut start = 0.0
  for index, id in scene.compositionOrder {
    guard scene.compositions.get(id) is Some(composition) else { continue }
    segments.push({
      kind: "composition",
      id,
      start,
      duration: composition.duration,
    })
    start += composition.duration
    let next_id = scene.compositionOrder.get(index + 1)
    for transition in scene.transitions.values() {
      if transition.fromId == id && Some(transition.toId) == next_id {
        segments.push({
          kind: "transition",
          id: transition.id,
          start,
          duration: transition.duration,
        })
        start += transition.duration
        break
      }
    }
  }
  segments
}

///|
pub fn scene_duration(scene : Scene) -> Double {
  let mut duration = scene_segments(scene).fold(init=0.0, fn(total, segment) {
    total + segment.duration
  })
  if scene.audioTracks is Some(tracks) {
    for track in tracks.values() {
      duration = duration.max(track.start + track.duration)
    }
  }
  for object in scene.objects.values() {
    if object.kind == "video" && object.playback is Some(playback) {
      if scene.compositions
        .values()
        .any(fn(comp) {
          comp.states.get(object.id).map(fn(s) { s.visible }).unwrap_or(false)
        }) {
        duration = duration.max(playback.start + playback.duration)
      }
    }
  }
  duration
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
