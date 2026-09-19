///|
pub fn object_insertion_changes(
  scene_id : String,
  additions : Array[@editor.ObjectInsertion],
) -> Array[@core.Any] {
  let changes = []
  for addition in additions {
    let id = addition.object.id
    changes.push(
      make_change(
        ["scenes", scene_id, "objects", id],
        encode_SceneObject(addition.object),
      ),
    )
    for (cid, state) in addition.states {
      changes.push(
        make_change(
          ["scenes", scene_id, "compositions", cid, "states", id],
          encode_ObjectState(state),
        ),
      )
    }
    for (tid, track) in addition.tracks {
      changes.push(
        make_change(
          ["scenes", scene_id, "transitions", tid, "tracks", id],
          encode_Track(track),
        ),
      )
    }
  }
  changes
}

///|
pub fn object_position_changes(
  scene_id : String,
  composition_id : String,
  positions : Array[(String, @scene.Point)],
) -> Array[@core.Any] {
  let changes = []
  for (id, point) in positions {
    changes.push(
      make_change(
        ["scenes", scene_id, "compositions", composition_id, "states", id, "x"],
        @core.any(point.x),
      ),
    )
    changes.push(
      make_change(
        ["scenes", scene_id, "compositions", composition_id, "states", id, "y"],
        @core.any(point.y),
      ),
    )
  }
  changes
}
