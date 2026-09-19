///|
pub fn edited_name(value : String) -> String? {
  let value = trim_text(value)
  if value.is_empty() {
    None
  } else {
    Some(value[:value.length().min(200)].to_owned())
  }
}

///|
/// ECMAScript WhiteSpace + LineTerminator, preserving the saved-name contract.
/// https://tc39.es/ecma262/multipage/ecmascript-language-lexical-grammar.html#sec-white-space
fn is_trim_space(code : Int) -> Bool {
  if (code >= 0x9 && code <= 0xd) || (code >= 0x2000 && code <= 0x200a) {
    return true
  }
  match code {
    0x20
    | 0xa0
    | 0x1680
    | 0x2028
    | 0x2029
    | 0x202f
    | 0x205f
    | 0x3000
    | 0xfeff => true
    _ => false
  }
}

///|
pub fn trim_text(value : String) -> StringView {
  let mut start = 0
  let mut end = value.length()
  while start < end && is_trim_space(value.code_unit_at(start).to_int()) {
    start += 1
  }
  while end > start && is_trim_space(value.code_unit_at(end - 1).to_int()) {
    end -= 1
  }
  value[start:end]
}

///|
fn copied_name(value : String) -> String {
  value[:value.length().min(195)].to_owned() + " copy"
}

///|
fn copy_media(asset : @scene.MediaAsset) -> @scene.MediaAsset {
  { ..asset, waveform: asset.waveform.map(fn(values) { values.copy() }), }
}

///|
pub fn copy_scene(
  source : @scene.Scene,
  allocate : (String) -> String,
) -> @scene.Scene {
  let objects : Map[String, String] = Map([])
  for id in source.objects.keys() {
    objects[id] = allocate("obj")
  }
  let compositions : Map[String, String] = Map([])
  for id in source.compositionOrder {
    compositions[id] = allocate("comp")
  }
  let groups : Map[String, String] = Map([])
  for object in source.objects.values() {
    if object.groupId is Some(group) &&
      !group.is_empty() &&
      !groups.contains(group) {
      groups[group] = allocate("group")
    }
  }
  let id = allocate("scene")
  let copied_audio : Map[String, @scene.AudioTrack] = Map([])
  if source.audioTracks is Some(tracks) {
    for track in tracks.values() {
      let id = allocate("audio")
      copied_audio[id] = { ..track, id, asset: copy_media(track.asset), }
    }
  }
  let copied_objects : Map[String, @scene.SceneObject] = Map([])
  for key, object in source.objects {
    let id = objects[key]
    copied_objects[id] = {
      ..object,
      id,
      groupId: object.groupId.bind(fn(group) { groups.get(group) }),
      media: object.media.map(copy_media),
    }
  }
  let copied_compositions : Map[String, @scene.Composition] = Map([])
  for key in source.compositionOrder {
    let source = source.compositions[key]
    let id = compositions[key]
    let states : Map[String, @scene.ObjectState] = Map([])
    for key, state in source.states {
      if objects.get(key) is Some(object_id) {
        states[object_id] = state
      }
    }
    copied_compositions[id] = {
      ..source,
      id,
      states,
      deleted: None,
      incomingTransitionId: None,
    }
  }
  let copied_transitions : Map[String, @scene.Transition] = Map([])
  for transition in source.transitions.values() {
    let id = allocate("transition")
    let tracks : Map[String, @scene.Track] = Map([])
    for key, track in transition.tracks {
      if objects.get(key) is Some(object_id) {
        tracks[object_id] = { ..track, objectId: object_id, }
      }
    }
    copied_transitions[id] = {
      ..transition,
      id,
      fromId: compositions[transition.fromId],
      toId: compositions[transition.toId],
      tracks,
    }
  }
  {
    ..source,
    id,
    name: copied_name(source.name),
    audioTracks: Some(copied_audio),
    compositionOrder: source.compositionOrder.map(fn(key) { compositions[key] }),
    objects: copied_objects,
    compositions: copied_compositions,
    transitions: copied_transitions,
    deleted: None,
  }
}

///|
pub fn index_of(values : Array[String], id : String) -> Int {
  for index, value in values {
    if value == id {
      return index
    }
  }
  -1
}

///|
pub fn selection_after_delete(order : Array[String], index : Int) -> String? {
  match order.get(index + 1) {
    Some(id) => Some(id)
    None => order.get(index - 1)
  }
}

///|
fn empty_transition(
  from_id : String,
  to_id : String,
  objects : Array[String],
  allocate : (String) -> String,
) -> @scene.Transition {
  @scene.implicit_transition(
    allocate("transition"),
    from_id,
    to_id,
    800.0,
    objects,
  )
}

///|
pub(all) struct CompositionInsertion {
  copy : @scene.Composition
  incoming : @scene.Transition
  outgoing_id : String?
}

///|
pub fn copy_composition(
  source : @scene.Composition,
  next_id : String?,
  links : Array[@scene.TransitionLink],
  objects : Array[String],
  allocate : (String) -> String,
) -> CompositionInsertion {
  let id = allocate("comp")
  let incoming = empty_transition(source.id, id, objects, allocate)
  let outgoing_id = links
    .iter()
    .find_first(fn(link) {
      link.from_id == source.id && Some(link.to_id) == next_id
    })
    .map(fn(link) { link.id })
  {
    copy: {
      ..source,
      id,
      name: copied_name(source.name),
      states: source.states.copy(),
      deleted: Some(false),
      incomingTransitionId: Some(incoming.id),
    },
    incoming,
    outgoing_id,
  }
}

///|
pub(all) struct CompositionRemoval {
  selected_id : String
  removed_transition_ids : Array[String]
  bridge : @scene.Transition?
}

///|
pub fn remove_composition(
  id : String,
  previous_id : String?,
  next_id : String?,
  links : Array[@scene.TransitionLink],
  objects : Array[String],
  allocate : (String) -> String,
) -> CompositionRemoval? {
  let bridge = match (previous_id, next_id) {
    (Some(from_id), Some(to_id)) =>
      Some(empty_transition(from_id, to_id, objects, allocate))
    _ => None
  }
  guard (match next_id {
      Some(id) => Some(id)
      None => previous_id
    })
    is Some(selected_id) else {
    return None
  }
  let removed_transition_ids = links
    .filter(fn(link) { link.from_id == id || link.to_id == id })
    .map(fn(link) { link.id })
  Some({ selected_id, removed_transition_ids, bridge, })
}
