///|
fn Compiler::depend(
  self : Compiler,
  path : Array[String],
) -> Unit raise CompileError {
  if path.any(fn(key) {
      key == "__proto__" || key == "constructor" || key == "prototype"
    }) {
    raise CompileError("編集対象が無効です。")
  }
  self.guards.push(path)
}

///|
fn Compiler::resolve(
  self : Compiler,
  value : String,
  kind : IdentityKind,
) -> String raise CompileError {
  match self.references.get(value) {
    Some((id, actual)) => {
      if actual != kind {
        raise CompileError(
          "参照名の対象の種類が一致しません。",
        )
      }
      id
    }
    None => value
  }
}

///|
fn Compiler::reserve(
  self : Compiler,
  name : String,
  kind : IdentityKind,
  allocate : (String) -> String,
) -> String raise CompileError {
  if self.references.contains(name) ||
    self.source.objects.contains(name) ||
    self.source.compositions.contains(name) ||
    self.source.transitions.contains(name) {
    raise CompileError(
      "新しい対象の参照名は、既存 ID と重複しない一意の名前にしてください。",
    )
  }
  let prefix = match kind {
    ObjectRef => "obj"
    CompositionRef => "comp"
    TransitionRef => "transition"
  }
  let id = allocate(prefix)
  self.references[name] = (id, kind)
  id
}

///|
fn Compiler::object(
  self : Compiler,
  id : String,
) -> @scene.SceneObject raise CompileError {
  let object = match self.objects.get(id) {
    Some(object) => object
    None =>
      raise CompileError(
        "編集対象のオブジェクトが見つかりません。",
      )
  }
  if object.locked {
    raise CompileError(
      "ロック中のオブジェクトは編集できません。",
    )
  }
  if !self.created.contains(id) {
    for key in ["id", "kind", "locked"] {
      self.depend(["objects", id, key])
    }
  }
  object
}

///|
fn Compiler::composition(
  self : Compiler,
  id : String,
) -> CompositionInfo raise CompileError {
  let composition = match self.compositions.get(id) {
    Some(value) => value
    None =>
      raise CompileError(
        "Composition が見つかりません。新しい Composition は appendComposition で先に宣言してください。",
      )
  }
  if !self.appended.contains(id) {
    self.depend(["compositions", id, "id"])
    self.depend(["compositions", id, "deleted"])
  }
  composition
}

///|
fn Compiler::transition(
  self : Compiler,
  id : String,
) -> TransitionInfo raise CompileError {
  let transition = match self.transitions.get(id) {
    Some(value) => value
    None =>
      raise CompileError(
        "Transition が見つかりません。新しい Transition は appendComposition で先に宣言してください。",
      )
  }
  self.composition(transition.from_id) |> ignore
  self.composition(transition.to_id) |> ignore
  if !self.new_transitions.contains(id) {
    for key in ["id", "duration", "fromId", "toId"] {
      self.depend(["transitions", id, key])
    }
  }
  transition
}

///|
fn Compiler::state(
  self : Compiler,
  composition : String,
  object_id : String,
) -> @scene.ObjectState? {
  if self.states.get(composition) is Some(states) &&
    states.get(object_id) is Some(value) {
    return Some(value)
  }
  if self.appended.contains(composition) {
    None
  } else {
    (self.source.state)(composition, object_id)
  }
}

///|
fn Compiler::set_state(
  self : Compiler,
  composition : String,
  object_id : String,
  value : @scene.ObjectState,
) -> Unit {
  let states = match self.states.get(composition) {
    Some(states) => states
    None => {
      let states = Map([])
      self.states[composition] = states
      states
    }
  }
  states[object_id] = value
}

///|
fn Compiler::all_states(
  self : Compiler,
  id : String,
) -> Map[String, @scene.ObjectState] {
  let states = Map([])
  for object_id in self.compositions[id].state_ids {
    if self.state(id, object_id) is Some(state) {
      states[object_id] = state
    }
  }
  if self.states.get(id) is Some(edits) {
    for object_id, state in edits {
      states[object_id] = state
    }
  }
  states
}

///|
fn Compiler::emit(self : Compiler, path : Array[String], value : Value) -> Unit {
  self.changes.push({ path, value, })
}

///|
fn Compiler::editable_track(
  self : Compiler,
  transition_id : String,
  object_id : String,
) -> (EditedTrack, TransitionInfo) raise CompileError {
  self.object(object_id) |> ignore
  let transition = self.transition(transition_id)
  if self.state(transition.from_id, object_id) is None &&
    self.state(transition.to_id, object_id) is None {
    raise CompileError(
      "この Transition にオブジェクトがありません。",
    )
  }
  let key = (transition_id, object_id)
  if self.tracks.get(key) is Some(entry) {
    return (entry, transition)
  }
  let path = ["transitions", transition_id, "tracks", object_id]
  let existing = !self.new_transitions.contains(transition_id) &&
    transition.track_ids.contains(object_id)
  let duration = self.durations
    .get(transition_id)
    .unwrap_or(transition.duration)
  let previous = if self.new_transitions.contains(transition_id) {
    None
  } else {
    (self.source.track)(transition_id, object_id)
  }
  let track = previous.unwrap_or({
    ..@scene.default_track(object_id, duration),
    implicit: if self.new_transitions.contains(transition_id) ||
      self.created.contains(object_id) {
      Some(true)
    } else {
      None
    },
  })
  let entry = {
    transition: transition_id,
    object_id,
    path,
    duration,
    existing,
    value: track,
    motion_edited: false,
    timing_fields: [],
  }
  self.tracks[key] = entry
  if existing {
    for property in ["start", "duration", "implicit"] {
      self.depend(path + [property])
    }
  }
  (entry, transition)
}
