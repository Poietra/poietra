///|
priv struct ProjectedTransition {
  mut duration : @core.Any
  tracks : Map[String, @core.Any]
}

///|
fn projected_tracks(input : @core.Any) -> Map[String, @core.Any] {
  let tracks = Map([])
  for id in @core.object_keys(input) {
    tracks[id] = input._get(id)
  }
  tracks
}

///|
fn check_projected_timing(
  doc : @core.Any,
  changes : Array[GuardedWrite],
  yjs : @core.Any,
) -> Unit {
  let transitions : Map[String, ProjectedTransition] = Map([])
  for change in changes {
    let path = change.path
    if path.length() == 4 && path[0] == "scenes" && path[2] == "transitions" {
      transitions[path_key(path)] = {
        duration: change.value._get("duration"),
        tracks: projected_tracks(change.value._get("tracks")),
      }
      continue
    }
    if path.length() < 5 ||
      path[0] != "scenes" ||
      path[2] != "transitions" ||
      (path[4] != "tracks" && path[4] != "duration") {
      continue
    }
    let base = path[:4].to_owned()
    let key = path_key(base)
    let entry = match transitions.get(key) {
      Some(entry) => entry
      None => {
        let duration = value(doc, base + ["duration"], yjs)
        if @core.typeof_(duration) != "number" {
          return fail("Transition が見つかりません。")
        }
        let entry = {
          duration,
          tracks: projected_tracks(value(doc, base + ["tracks"], yjs)),
        }
        transitions[key] = entry
        entry
      }
    }
    if path[4] == "duration" {
      entry.duration = change.value
    } else if path.length() == 6 {
      entry.tracks[path[5]] = change.value
    } else {
      if path.length() < 7 {
        return fail(
          "編集対象のアニメーションが見つかりません。",
        )
      }
      let track = match entry.tracks.get(path[5]) {
        Some(track) if truthy(track) => copy_record(track)
        _ =>
          return fail(
            "編集対象のアニメーションが見つかりません。",
          )
      }
      // Only a touched track is copied. All untouched timing values remain
      // shared read-only inputs while coupled constraints are checked together.
      let mut target = track
      for index = 6; index < path.length() - 1; index = index + 1 {
        let previous = target._get(path[index])
        if @core.is_nullish(previous) || @core.typeof_(previous) != "object" {
          return fail(
            "編集対象のキーフレームが見つかりません。",
          )
        }
        let child = copy_record(previous)
        target._set(path[index], child)
        target = child
      }
      target._set(path[path.length() - 1], change.value)
      entry.tracks[path[5]] = track
    }
  }
  for entry in transitions.values() {
    let duration = valid_duration(entry.duration)
    for track in entry.tracks.values() {
      if !truthy(track) {
        return fail(
          "編集対象のアニメーションが見つかりません。",
        )
      }
      @boundary.validate_animation_track(track, duration)
    }
  }
}

///|
pub fn validate_proposal_for_apply(
  doc : @core.Any,
  proposal : @core.Any,
  yjs : @core.Any,
) -> Unit {
  validate(doc, proposal, yjs) |> ignore
}

///|
priv struct PreparedWrite {
  parent : @core.Any
  key : String
  value : @core.Any?
}

///|
pub fn apply_proposal(
  doc : @core.Any,
  proposal : @core.Any,
  origin : @core.Any,
  yjs : @core.Any,
) -> Unit {
  let validated = validate(doc, proposal, yjs)
  // Yjs transactions do not roll back. Resolve all parents and construct every
  // new shared value before entering the single publication transaction.
  let writes = validated.changes.map(fn(change) {
    PreparedWrite::{
      parent: change.parent,
      key: change.path[change.path.length() - 1],
      value: if @core.is_undefined(change.value) {
        None
      } else {
        Some(@boundary.to_shared(change.value, yjs))
      },
    }
  })
  let appends = validated.appends.map(fn(append) {
    (append.order, FixedArray::from_array(append.ids[:]))
  })
  if validated.changes.any(fn(change) {
      @boundary.change_requires_v2(change.path, change.value)
    }) {
    @boundary.upgrade_document_format(doc)
  }
  doc._call("transact", [
    @core.any(fn() {
      for write in writes {
        match write.value {
          None => write.parent._call("delete", [@core.any(write.key)]) |> ignore
          Some(value) =>
            write.parent._call("set", [@core.any(write.key), value]) |> ignore
        }
      }
      for (order, ids) in appends {
        order._call("push", [@core.any(ids)]) |> ignore
      }
    }),
    origin,
  ])
  |> ignore
}
