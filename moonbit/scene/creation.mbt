///|
pub fn empty_composition(
  id : String,
  name : String,
  duration : Double,
  accent : String,
) -> Composition {
  {
    id,
    name,
    duration,
    accent,
    states: Map([]),
    deleted: None,
    incomingTransitionId: None,
  }
}

///|
pub fn blank_scene(id : String, name : String) -> Scene {
  let cid = id + "-comp-1"
  {
    id,
    name,
    width: 1280.0,
    height: 720.0,
    background: "#08090b",
    objects: Map([]),
    audioTracks: Some(Map([])),
    compositionOrder: [cid],
    compositions: Map([
      (cid, empty_composition(cid, "Composition 1", 1000.0, "#f4ce55")),
    ]),
    transitions: Map([]),
    deleted: None,
  }
}

///|
pub fn implicit_transition(
  id : String,
  from_id : String,
  to_id : String,
  duration : Double,
  objects : Array[String],
) -> Transition {
  let tracks = Map([])
  for object_id in objects {
    tracks[object_id] = {
      ..default_track(object_id, duration),
      implicit: Some(true),
    }
  }
  { id, fromId: from_id, toId: to_id, duration, tracks, }
}
