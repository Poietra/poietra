///|
/// The same insertion plan serves manual creation, clipboard and asset imports.
pub(all) struct ObjectInsertion {
  object : @scene.SceneObject
  states : Array[(String, @scene.ObjectState)]
  tracks : Array[(String, @scene.Track)]
}

///|
/// Read only creation metadata, never all existing Composition states.
pub(all) struct ObjectCreationTarget {
  objects : Array[(@scene.ObjectKind, Double)]
  compositions : Array[String]
  transitions : Array[(String, Double)]
}

///|
pub(all) enum ObjectCreationError {
  MissingComposition
  ObjectLimit
} derive(Eq, Debug)

///|
pub fn object_kind_label(kind : @scene.ObjectKind) -> String {
  match kind {
    Circle => "Circle"
    Rectangle => "Rectangle"
    Text => "Text"
    Equation => "Equation"
    Path => "Path"
    Arrow => "Arrow"
    NumberLine => "Number line"
    Image => "Image"
    Video => "Video"
  }
}

///|
pub fn create_object(
  target : ObjectCreationTarget,
  composition : String,
  kind : @scene.ObjectKind,
  state : @scene.ObjectState,
  image : @scene.ImageAsset?,
  name : String?,
  allocate : (String) -> String,
) -> Result[ObjectInsertion, ObjectCreationError] {
  if !target.compositions.contains(composition) {
    return Err(MissingComposition)
  }
  if target.objects.length() >= 500 {
    return Err(ObjectLimit)
  }
  let mut count = 1
  let mut order = -1.0
  for (existing, position) in target.objects {
    if existing == kind {
      count += 1
    }
    order = order.max(position)
  }
  let name = name.unwrap_or("")
  let name = if name.is_empty() {
    object_kind_label(kind) + " " + count.to_string()
  } else {
    name[:name.length().min(200)].to_owned()
  }
  let id = allocate("obj")
  Ok({
    object: {
      id,
      name,
      kind,
      order: order + 1.0,
      groupId: None,
      locked: false,
      image,
      media: None,
      playback: None,
    },
    states: target.compositions.map(fn(cid) {
      (cid, { ..state, visible: cid == composition, })
    }),
    tracks: target.transitions.map(fn(link) {
      let (tid, duration) = link
      (tid, { ..@scene.default_track(id, duration), implicit: Some(true), })
    }),
  })
}

///|
/// None for the lock means that the object no longer exists. A missing state
/// must not be recreated by an in-flight drag or hide command.
pub(all) struct StateTarget[T] {
  id : String
  locked : Bool?
  state : T?
}

///|
pub fn[T] editable_state_ids(targets : Array[StateTarget[T]]) -> Array[String] {
  [
    for target in targets if target.locked == Some(false) &&
    target.state is Some(_) => target.id
  ]
}

///|
pub fn translated_objects(
  targets : Array[StateTarget[@scene.Point]],
  dx : Double,
  dy : Double,
) -> Array[(String, @scene.Point)] {
  let result : Array[(String, @scene.Point)] = []
  for target in targets {
    if target.locked == Some(false) && target.state is Some(start) {
      result.push(
        (
          target.id,
          {
            x: ((start.x + dx) * 10.0).round() / 10.0,
            y: ((start.y + dy) * 10.0).round() / 10.0,
          },
        ),
      )
    }
  }
  result
}
