///|
fn Session::allow_delete(
  self : Session,
  item : @core.Any,
  plan : CreationPlan,
  durations : @collection.JsSet[@core.Any],
  prior : @core.Any,
) -> Bool {
  let content = item._get("content")
  let is_type = instance_of(content, self.yjs._get("ContentType"))
  if is_type &&
    self.is_map(content._get("type")) &&
    plan.containers.has(content._get("type")) {
    return false
  }
  let parent = item._get("parent")
  let key = item._get("parentSub")
  if self.is_map(parent) &&
    @core.typeof_(key) == "string" &&
    plan.retained_fields.get(parent) is Some(fields) &&
    fields.contains(key.cast()) {
    return false
  }
  if @core.equal(key, @core.any("duration")) &&
    self.is_map(parent) &&
    durations.has(parent) {
    return false
  }
  if @core.equal(key, @core.any("deleted")) &&
    self.is_map(parent) &&
    plan.revived_compositions.has(parent) {
    return false
  }
  if self.is_array(parent) && plan.order_entries.get(parent) is Some(entries) {
    let ids : FixedArray[@core.Any] = content._call("getContent", []).cast()
    // A single native Item may contain several IDs. Keep the complete batch.
    if ids
      .iter()
      .any(fn(id) {
        @core.typeof_(id) == "string" && entries.contains(id.cast())
      }) {
      return false
    }
  }
  // Yjs visits children first: keep every nested field under a retained root.
  let mut node = if is_type { content._get("type") } else { parent }
  while instance_of(node, self.yjs._get("AbstractType")) {
    if self.is_map(node) && plan.roots.has(node) {
      return false
    }
    let ancestor = node._get("_item")
    node = if @core.is_nullish(ancestor) {
      @core.null()
    } else {
      ancestor._get("parent")
    }
  }
  (prior.cast() : (@core.Any) -> Bool)(item)
}

///|
fn Session::protected_step(
  self : Session,
  direction : Direction,
  plan : CreationPlan,
  durations : @collection.JsSet[@core.Any],
) -> Bool raise {
  let stack = direction.stack(self.manager)
  let action = top(stack)
  let original_deletions = action._get("deletions")
  let omitted = []
  durations.forEach(fn(transition) {
    omitted.append(field_history(transition, "duration"))
  })
  plan.activated_tracks.forEach(fn(track) {
    for key in keys(track._get("_map")) {
      omitted.append(field_history(track, key))
    }
  })
  plan.timing_parents.forEach(fn(fields, track) {
    for key in fields {
      omitted.append(field_history(track, key))
    }
  })
  plan.retained_fields.forEach(fn(fields, parent) {
    for key in fields {
      omitted.append(field_history(parent, key))
    }
  })
  plan.revived_compositions.forEach(fn(composition) {
    omitted.append(field_history(composition, "deleted"))
  })
  if !omitted.is_empty() {
    action._set("deletions", self.without_items(original_deletions, omitted))
  }
  let prior = self.manager._get("deleteFilter")
  self.manager._set(
    "deleteFilter",
    @core.any(fn(item : @core.Any) {
      self.allow_delete(item, plan, durations, prior)
    }),
  )
  // Inspect no-op actions separately. Yjs must not silently skip into an older
  // creation whose dependencies have not been planned by this step.
  let earlier = hide_earlier(stack)
  defer {
    restore_stack(stack, earlier)
    self.manager._set("deleteFilter", prior)
    action._set("deletions", original_deletions)
  }
  truthy(@core.throwable(fn() { self.manager._call(direction.name(), []) }))
}

///|
fn Session::undo_step(self : Session) -> Int raise {
  self.counts = empty_counts()
  while truthy(self.manager._call("canUndo", [])) {
    let action = top(self.manager._get("undoStack"))
    let plan = self.shared_creations(action)
    let transitions = self.transitions()
    let durations = self.required_durations(plan, action, transitions)
    self.assert_tracks_fit(action, durations, Undo, plan.roots, transitions)
    let tracks = plan.track_count()
    let changed = self.protected_step(Undo, plan, durations)
    if plan.roots.size() > 0 ||
      plan.retained_fields.size() > 0 ||
      durations.size() > 0 {
      plan.dependent_tracks.forEach(fn(track) {
        self.retained_tracks.add(track) |> ignore
      })
      self.counts = {
        audio: plan.audio.size(),
        objects: plan.objects.size(),
        durations: durations.size(),
        compositions: plan.compositions.size(),
      }
      self.manager._call("stopCapturing", []) |> ignore
      return tracks
    }
    if changed {
      return 0
    }
  }
  0
}

///|
fn Session::redo_step(self : Session) -> Int raise {
  let plan = empty_creations()
  while truthy(self.manager._call("canRedo", [])) {
    let action = top(self.manager._get("redoStack"))
    let transitions = self.transitions()
    let durations = self.required_durations(plan, action, transitions)
    self.assert_tracks_fit(action, durations, Redo, plan.roots, transitions)
    let changed = self.protected_step(Redo, plan, durations)
    if durations.size() > 0 {
      self.manager._call("stopCapturing", []) |> ignore
      return durations.size()
    }
    if changed {
      return 0
    }
  }
  0
}

///|
fn Session::rollback(self : Session, expected : @core.Any) -> Bool raise {
  let undo_stack = self.manager._get("undoStack")
  if !@core.equal(top(undo_stack), expected) {
    return false
  }
  let redo_stack = self.manager._get("redoStack")
  let earlier = hide_earlier(undo_stack)
  let earlier_redo = redo_stack._call("splice", [@core.any(0)])
  defer {
    // Yjs clear() replaces the redo array; restore into its current identity.
    restore_stack(self.manager._get("redoStack"), earlier_redo)
    self.manager._call("stopCapturing", []) |> ignore
  }
  {
    defer restore_stack(self.manager._get("undoStack"), earlier)
    self.undo_step() |> ignore
  }
  // Canceled gestures are not redoable. Unrelated Redo history survives.
  @core.throwable(fn() {
    self.manager._call("clear", [@core.any(false), @core.any(true)])
  })
  |> ignore
  true
}

///|
pub fn undo(session : Session) -> Int {
  session.undo_step() catch {
    error => {
      @core.throw_(native_error(error))
      0
    }
  }
}

///|
pub fn redo(session : Session) -> Int {
  session.redo_step() catch {
    error => {
      @core.throw_(native_error(error))
      0
    }
  }
}

///|
pub fn rollback_gesture(session : Session, expected : @core.Any) -> Bool {
  session.rollback(expected) catch {
    error => {
      @core.throw_(native_error(error))
      false
    }
  }
}
