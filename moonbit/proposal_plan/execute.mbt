///|
fn Compiler::append(
  self : Compiler,
  reference : String,
  transition_reference : String,
  name : String,
  duration : Double,
  transition_duration : Double,
) -> Unit raise CompileError {
  let from = match self.order.last() {
    Some(id) => id
    None => raise CompileError("Composition が見つかりません。")
  }
  let previous = self.composition(from)
  if !self.appended.contains(from) {
    self.depend(["compositions", from, "states"])
    for oid in self.source.compositions[from].state_ids {
      for key in ["id", "kind"] {
        self.depend(["objects", oid, key])
      }
    }
    if self.source.deleted_compositions.contains(from) {
      self.emit(["compositions", from, "deleted"], ScalarValue(Boolean(false)))
    }
  }
  let id = self.resolve(reference, CompositionRef)
  let tid = self.resolve(transition_reference, TransitionRef)
  let states = self.all_states(from)
  for oid, pending in self.created {
    if !pending.declared {
      states[oid] = { ..pending.state, visible: pending.composition == id, }
    }
  }
  self.states[id] = states
  self.compositions[id] = {
    id,
    name,
    duration,
    accent: previous.accent,
    state_ids: states.keys().to_array(),
  }
  self.order.push(id)
  self.appended.push(id)
  self.transitions[tid] = {
    id: tid,
    from_id: from,
    to_id: id,
    duration: self.durations.get(tid).unwrap_or(transition_duration),
    track_ids: self.objects.keys().to_array(),
  }
  self.new_transitions.add(tid)
}

///|
fn Compiler::execute(
  self : Compiler,
  index : Int,
  operation : Operation,
) -> Unit raise CompileError {
  match operation {
    Append(reference, transition, name, duration, travel) =>
      self.append(reference, transition, name, duration, travel)
    Create(creation) => {
      self.composition(self.resolve(creation.composition, CompositionRef))
      |> ignore
      self.created[self.declarations[index]].declared = true
    }
    State(cid, oid, field, value) => {
      let cid = self.resolve(cid, CompositionRef)
      let oid = self.resolve(oid, ObjectRef)
      let object = self.object(oid)
      self.composition(cid) |> ignore
      let state = match self.state(cid, oid) {
        Some(state) => state
        None =>
          raise CompileError("編集対象の状態が見つかりません。")
      }
      self.set_state(cid, oid, change_state(state, field, value, object.kind))
      if !self.created.contains(oid) && !self.appended.contains(cid) {
        self.emit(
          ["compositions", cid, "states", oid, field_name(field)],
          ScalarValue(value),
        )
      }
    }
    ShapePath(cid, oid, path) => {
      let cid = self.resolve(cid, CompositionRef)
      let oid = self.resolve(oid, ObjectRef)
      let object = self.object(oid)
      self.composition(cid) |> ignore
      if object.kind != Path {
        raise CompileError(
          "図形の制御点を編集できるのはベジェ曲線だけです。移動経路には setMotionPath を使ってください。",
        )
      }
      let state = match self.state(cid, oid) {
        Some(state) => state
        None =>
          raise CompileError("編集対象の状態が見つかりません。")
      }
      self.set_state(cid, oid, { ..state, path, })
      if !self.created.contains(oid) && !self.appended.contains(cid) {
        let base = ["compositions", cid, "states", oid]
        for key in ["x", "y", "width", "height", "rotation"] {
          self.depend(base + [key])
        }
        self.emit(base + ["path"], PathValue(Some(path)))
      }
    }
    Track(tid, oid, edit) => self.edit_track(tid, oid, edit)
    CompositionDuration(cid, duration) => {
      let cid = self.resolve(cid, CompositionRef)
      let composition = self.composition(cid)
      valid_duration(duration)
      self.compositions[cid] = { ..composition, duration, }
      if !self.appended.contains(cid) {
        self.emit(
          ["compositions", cid, "duration"],
          ScalarValue(Number(duration)),
        )
      }
    }
    TransitionDuration(tid, _) =>
      self.transition(self.resolve(tid, TransitionRef)) |> ignore
  }
}
