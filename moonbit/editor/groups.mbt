///|
pub(all) struct GroupObject {
  id : String
  group_id : String?
  locked : Bool
  order : Double
}

///|
pub fn group_members(
  objects : Array[GroupObject],
  group_id : String,
) -> Array[String] {
  let indices : Array[Int] = []
  for index, object in objects {
    if object.group_id == Some(group_id) {
      indices.push(index)
    }
  }
  indices.sort_by(fn(a, b) {
    let delta = objects[a].order - objects[b].order
    if delta.is_nan() || delta == 0.0 {
      a - b
    } else if delta < 0.0 {
      -1
    } else {
      1
    }
  })
  indices.map(fn(i) { objects[i].id })
}

///|
pub fn editable_group_members(
  objects : Array[GroupObject],
  selected : Array[String],
) -> Array[String] {
  let selected = Set::from_array(selected)
  let ids : Set[String] = Set([])
  let groups : Set[String] = Set([])
  for object in objects {
    if !object.locked && selected.contains(object.id) {
      ids.add(object.id)
      if object.group_id is Some(group) && !group.is_empty() {
        groups.add(group)
      }
    }
  }
  [
    for object in objects if !object.locked &&
    (
      ids.contains(object.id) ||
      (
        object.group_id is Some(group) &&
        !group.is_empty() &&
        groups.contains(group)
      )
    ) => object.id
  ]
}

///|
pub(all) enum Presence {
  Entering
  Leaving
  Both
} derive(Eq)

///|
pub fn presence(from : Bool, to : Bool) -> Presence? {
  match (from, to) {
    (false, false) => None
    (false, true) => Some(Entering)
    (true, false) => Some(Leaving)
    _ => Some(Both)
  }
}

///|
pub fn presence_name(value : Presence) -> String {
  match value {
    Entering => "enter"
    Leaving => "exit"
    Both => "both"
  }
}

///|
pub(all) struct AnimationCandidate {
  id : String
  locked : Bool
  from_visible : Bool
  to_visible : Bool
}

///|
pub(all) enum AnimationExclusion {
  Locked
  Hidden
} derive(Eq, Debug)

///|
pub(all) struct AnimationSelection {
  targets : Array[(String, Presence)]
  excluded : Array[(String, AnimationExclusion)]
}

///|
/// Classify once without resolving/allocating a display track. Commands can
/// consume the selected identities directly; UI adapters add display values.
pub fn select_animations(
  candidates : Array[AnimationCandidate],
) -> AnimationSelection {
  let selected : Set[String] = Set([])
  let targets : Array[(String, Presence)] = []
  let excluded : Array[(String, AnimationExclusion)] = []
  for candidate in candidates {
    if selected.contains(candidate.id) {
      continue
    }
    selected.add(candidate.id)
    if candidate.locked {
      excluded.push((candidate.id, Locked))
    } else {
      match presence(candidate.from_visible, candidate.to_visible) {
        None => excluded.push((candidate.id, Hidden))
        Some(presence) => targets.push((candidate.id, presence))
      }
    }
  }
  { targets, excluded, }
}

///|
pub(all) struct EditableTrack {
  object_id : String
  stored : @scene.Track?
}

///|
pub(all) struct GroupTiming {
  existing : Bool
  start : Double
  duration : Double
}

///|
pub fn group_timing_limits(
  targets : Array[GroupTiming],
  duration : Double,
) -> (Double, Double) {
  let mut start = duration
  let mut length = duration
  for target in targets {
    if target.existing {
      start = @scene.minimum(start, duration - target.duration)
    }
    length = @scene.minimum(length, duration - target.start)
  }
  (@scene.maximum(0.0, start), @scene.maximum(0.0, length))
}

///|
pub(all) enum WriteOrder {
  Together
  Sequential
}

///|
pub fn write_order_name(value : WriteOrder) -> String {
  match value {
    Together => "together"
    Sequential => "sequential"
  }
}

///|
pub(all) enum TrackField {
  Kind(@scene.AnimationKind)
  Start(Double)
  Duration(Double)
  Curve(@scene.Easing)
  Order(WriteOrder)
}

///|
pub(all) enum TrackValue {
  Whole(@scene.Track)
  Field(TrackField)
  Flag(Bool)
}

///|
pub(all) struct TrackEdit {
  object_id : String
  key : String?
  value : TrackValue
}

///|
pub(all) enum GroupError {
  BaseBounds
  PropertyBounds
  InvalidEasing
}

///|
pub fn field_name(field : TrackField) -> String {
  match field {
    Kind(_) => "type"
    Start(_) => "start"
    Duration(_) => "duration"
    Curve(_) => "easing"
    Order(_) => "order"
  }
}

///|
fn number_equal(a : Double, b : Double) -> Bool {
  if a.is_nan() && b.is_nan() {
    true
  } else if a == 0.0 && b == 0.0 {
    1.0 / a == 1.0 / b
  } else {
    a == b
  }
}

///|
fn field_equal(track : @scene.Track, field : TrackField) -> Bool {
  match field {
    Kind(kind) => track.type_ == kind
    Start(value) => number_equal(track.start, value)
    Duration(value) => number_equal(track.duration, value)
    Curve(value) => track.easing == value
    Order(value) => track.order == write_order_name(value)
  }
}

///|
/// Prepare a complete typed batch. Existing tracks write only changed leaves,
/// preserving unrelated peer property edits during concurrent editing and Undo.
pub fn group_animation_plan(
  targets : Array[EditableTrack],
  limit : Double,
  patch : Array[TrackField],
) -> Result[Array[TrackEdit], GroupError] {
  let result : Array[TrackEdit] = []
  let channels = @scene.property_channels()
  for target in targets {
    let base = @scene.resolve_track(target.stored, target.object_id, limit)
    let implicit = target.stored
      .map(fn(t) { t.implicit == Some(true) })
      .unwrap_or(false)
    let mut track = if implicit {
      { ..base, implicit: Some(false), }
    } else {
      base
    }
    let mut start : Double? = None
    let mut has_duration = false
    for field in patch {
      track = match field {
        Kind(kind) => { ..track, type_: kind, }
        Start(value) => {
          start = Some(value)
          { ..track, start: value, }
        }
        Duration(value) => {
          has_duration = true
          { ..track, duration: value, }
        }
        Curve(easing) => { ..track, easing, }
        Order(order) => { ..track, order: write_order_name(order), }
      }
    }
    if (target.stored is None || implicit) &&
      start is Some(start) &&
      !has_duration {
      track = { ..track, duration: @scene.maximum(0.0, limit - start), }
    }
    if !@scene.valid_timing_bounds(track.start, track.duration, limit) {
      return Err(BaseBounds)
    }
    if !@scene.valid_easing(track.easing) {
      return Err(InvalidEasing)
    }
    for channel in channels {
      if @scene.timing_override(track, channel) is Some(timing) {
        if !@scene.valid_timing_bounds(timing.start, timing.duration, limit) {
          return Err(PropertyBounds)
        }
        if !@scene.valid_easing(timing.easing) {
          return Err(InvalidEasing)
        }
      }
    }
    if target.stored is None {
      result.push({
        object_id: target.object_id,
        key: None,
        value: Whole(track),
      })
    } else {
      if implicit {
        result.push({
          object_id: target.object_id,
          key: Some("start"),
          value: Field(Start(track.start)),
        })
        result.push({
          object_id: target.object_id,
          key: Some("duration"),
          value: Field(Duration(track.duration)),
        })
        result.push({
          object_id: target.object_id,
          key: Some("implicit"),
          value: Flag(false),
        })
      }
      for field in patch {
        if !field_equal(base, field) {
          result.push({
            object_id: target.object_id,
            key: Some(field_name(field)),
            value: Field(field),
          })
        }
      }
    }
  }
  Ok(result)
}
