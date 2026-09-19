///|
/// Decode only timeline metadata. Image data, paths and state styles do not cross
/// the boundary when an inspector asks for duration or a playhead position.
fn decode_timeline(value : @core.Any) -> @scene.TimelineData {
  let compositions = value._get("compositions")
  let holds = Map([])
  for id in @core.object_keys(compositions) {
    let composition = compositions._get(id)
    if truthy(composition) {
      holds[id] = composition._get("duration").cast()
    }
  }
  let transitions = value._get("transitions")
  let links : Array[@scene.TimelineLink] = []
  for id in @core.object_keys(transitions) {
    let link = transitions._get(id)
    links.push({
      id: link._get("id").cast(),
      from_id: link._get("fromId").cast(),
      to_id: link._get("toId").cast(),
      duration: link._get("duration").cast(),
    })
  }
  let media_ends : Array[Double] = []
  let audio = value._get("audioTracks")
  if !@core.is_nullish(audio) {
    for id in @core.object_keys(audio) {
      let track = audio._get(id)
      let start : Double = track._get("start").cast()
      let duration : Double = track._get("duration").cast()
      media_ends.push(start + duration)
    }
  }
  let objects = value._get("objects")
  for id in @core.object_keys(objects) {
    let object = objects._get(id)
    let playback = object._get("playback")
    if !strict_equal(object._get("kind"), @core.any("video")) ||
      !truthy(playback) {
      continue
    }
    for cid in @core.object_keys(compositions) {
      let state = compositions
        ._get(cid)
        ._get("states")
        ._get(object._get("id").cast())
      if !@core.is_nullish(state) && truthy(state._get("visible")) {
        let start : Double = playback._get("start").cast()
        let duration : Double = playback._get("duration").cast()
        media_ends.push(start + duration)
        break
      }
    }
  }
  {
    order: decode_array(value._get("compositionOrder"), fn(v) { v.cast() }),
    holds,
    links,
    media_ends,
  }
}

///|
extern "js" fn make_project_segment(
  scene : @core.Any,
  start : Double,
  duration : Double,
) -> @core.Any =
  #|(scene, start, duration) => ({scene, start, duration})

///|
pub fn project_segments(project : @core.Any) -> FixedArray[@core.Any] {
  let order : FixedArray[String] = project._get("sceneOrder").cast()
  let scenes = project._get("scenes")
  let result : Array[@core.Any] = []
  let mut start = 0.0
  for id in order {
    let scene = scenes._get(id)
    if !truthy(scene) {
      continue
    }
    let duration = @scene.timeline_duration(decode_timeline(scene))
    result.push(make_project_segment(scene, start, duration))
    start += duration
  }
  FixedArray::makei(result.length(), fn(i) { result[i] })
}

///|
pub fn project_duration(project : @core.Any) -> Double {
  let mut total = 0.0
  for segment in project_segments(project) {
    let duration : Double = segment._get("duration").cast()
    total += duration
  }
  total
}

///|
pub fn project_segment_at(
  segments : FixedArray[@core.Any],
  time : Double,
) -> @core.Any {
  let bounds = Array::makei(segments.length(), fn(i) {
    (segments[i]._get("start").cast(), segments[i]._get("duration").cast())
  })
  match @scene.project_segment_at(bounds, time) {
    Some(index) => segments[index]
    None => @core.undefined()
  }
}
