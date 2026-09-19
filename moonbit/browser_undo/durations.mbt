///|
priv enum Direction {
  Undo
  Redo
}

///|
fn Direction::name(self : Direction) -> String {
  match self {
    Undo => "undo"
    Redo => "redo"
  }
}

///|
fn Direction::stack(self : Direction, manager : @core.Any) -> @core.Any {
  manager._get(
    match self {
      Undo => "undoStack"
      Redo => "redoStack"
    },
  )
}

///|
fn Session::projected_track_end(
  self : Session,
  action : @core.Any,
  track : @core.Any,
  retained : Bool,
  retained_timings : @collection.JsSet[@core.Any],
) -> Double {
  let field = fn(map : @core.Any, key : String) {
    if retained || retained_timings.has(map) {
      get(map, key)
    } else {
      self.field_after_step(action, map, key)
    }
  }
  let end = fn(map : @core.Any) {
    let start = field(map, "start")
    let duration = field(map, "duration")
    if @core.typeof_(start) == "number" && @core.typeof_(duration) == "number" {
      (start.cast() : Double) + (duration.cast() : Double)
    } else {
      0.0
    }
  }
  let mut maximum = if @core.equal(field(track, "implicit"), @core.any(true)) {
    0.0
  } else {
    end(track)
  }
  for key in timing_keys() {
    let current = get(track, key)
    let timing = if self.is_map(current) && retained_timings.has(current) {
      current
    } else {
      field(track, key)
    }
    if self.is_map(timing) {
      maximum = maximum.max(end(timing))
    }
  }
  maximum
}

///|
fn Session::transitions(self : Session) -> Array[@core.Any] {
  let result = []
  let scenes = get(self.root, "scenes")
  if !self.is_map(scenes) {
    return result
  }
  for scene in values(scenes) {
    if !self.is_map(scene) {
      continue
    }
    let transitions = get(scene, "transitions")
    if !self.is_map(transitions) {
      continue
    }
    for transition in values(transitions) {
      if self.is_map(transition) {
        result.push(transition)
      }
    }
  }
  result
}

///|
fn Session::required_durations(
  self : Session,
  plan : CreationPlan,
  action : @core.Any,
  transitions : Array[@core.Any],
) -> @collection.JsSet[@core.Any] {
  let durations = @collection.JsSet::new()
  for transition in transitions {
    let tracks = get(transition, "tracks")
    if !self.is_map(tracks) {
      continue
    }
    let duration = self.field_after_undo(action, transition, "duration")
    if @core.typeof_(duration) != "number" {
      continue
    }
    for track in values(tracks) {
      if !self.is_map(track) ||
        (
          !plan.dependent_tracks.has(track) &&
          !self.retained_tracks.has(track) &&
          !self.peer_tracks.has(track)
        ) {
        continue
      }
      if self.projected_track_end(
          action,
          track,
          plan.roots.has(track),
          plan.roots,
        ) >
        (duration.cast() : Double) {
        durations.add(transition) |> ignore
        break
      }
    }
  }
  durations
}

///|
fn Session::assert_tracks_fit(
  self : Session,
  action : @core.Any,
  kept : @collection.JsSet[@core.Any],
  direction : Direction,
  retained : @collection.JsSet[@core.Any],
  transitions : Array[@core.Any],
) -> Unit raise {
  for transition in transitions {
    let tracks = get(transition, "tracks")
    if !self.is_map(tracks) {
      continue
    }
    let duration = if kept.has(transition) {
      get(transition, "duration")
    } else {
      self.field_after_undo(action, transition, "duration")
    }
    if @core.typeof_(duration) != "number" {
      continue
    }
    // Include deleted child maps and restored channels before touching stacks.
    for key in keys(tracks._get("_map")) {
      let current = get(tracks, key)
      let track = if self.is_map(current) && retained.has(current) {
        current
      } else {
        self.field_after_step(action, tracks, key)
      }
      if self.is_map(track) &&
        self.projected_track_end(action, track, retained.has(track), retained) >
        (duration.cast() : Double) {
        @core.throwable(fn() {
          @core.throw_error(
            match direction {
              Undo =>
                "この時間設定は復元できません。現在の長さに合わせて改めて編集してください。"
              Redo =>
                "共同編集者が Transition を短くしたため、このアニメーションをやり直せません。現在の長さに合わせて改めて編集してください。"
            },
          )
        })
      }
    }
  }
}
