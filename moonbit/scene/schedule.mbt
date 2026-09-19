///|
/// Timeline queries need structure and media endpoints, not payloads or geometry.
pub(all) struct TimelineLink {
  id : String
  from_id : String
  to_id : String
  duration : Double
}

///|
pub(all) struct TimelineData {
  order : Array[String]
  holds : Map[String, Double]
  links : Array[TimelineLink]
  media_ends : Array[Double]
}

///|
pub fn timeline_segments(data : TimelineData) -> Array[Segment] {
  let links : Map[(String, String), TimelineLink] = Map([])
  for link in data.links {
    let key = (link.from_id, link.to_id)
    if !links.contains(key) {
      links[key] = link
    }
  }
  let result : Array[Segment] = []
  let mut start = 0.0
  for index, id in data.order {
    guard data.holds.get(id) is Some(duration) else { continue }
    result.push({ kind: "composition", id, start, duration, })
    start += duration
    if data.order.get(index + 1) is Some(next_id) &&
      links.get((id, next_id)) is Some(link) {
      result.push({
        kind: "transition",
        id: link.id,
        start,
        duration: link.duration,
      })
      start += link.duration
    }
  }
  result
}

///|
pub fn timeline_duration(data : TimelineData) -> Double {
  let mut result = timeline_segments(data).fold(init=0.0, fn(total, segment) {
    total + segment.duration
  })
  for end in data.media_ends {
    result = maximum(result, end)
  }
  result
}

///|
pub fn project_segment_at(
  bounds : Array[(Double, Double)],
  time : Double,
) -> Int? {
  let mut last : Int? = None
  for index, bound in bounds {
    if bound.1 > 0.0 {
      if time < bound.0 + bound.1 {
        return Some(index)
      }
      last = Some(index)
    }
  }
  match last {
    Some(_) => last
    None => if bounds.is_empty() { None } else { Some(0) }
  }
}

///|
pub fn scene_timeline(scene : Scene) -> TimelineData {
  let holds = Map([])
  for id, composition in scene.compositions {
    holds[id] = composition.duration
  }
  let links = scene.transitions
    .values()
    .map(fn(link) {
      TimelineLink::{
        id: link.id,
        from_id: link.fromId,
        to_id: link.toId,
        duration: link.duration,
      }
    })
    .collect()
  let media_ends = []
  if scene.audioTracks is Some(tracks) {
    for track in tracks.values() {
      media_ends.push(track.start + track.duration)
    }
  }
  for object in scene.objects.values() {
    if object.kind == Video &&
      object.playback is Some(playback) &&
      scene.compositions
      .values()
      .any(fn(comp) {
        comp.states.get(object.id).map(fn(s) { s.visible }).unwrap_or(false)
      }) {
      media_ends.push(playback.start + playback.duration)
    }
  }
  { order: scene.compositionOrder, holds, links, media_ends, }
}
