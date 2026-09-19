///|
priv struct CreationPlan {
  roots : @collection.JsSet[@core.Any]
  containers : @collection.JsSet[@core.Any]
  activated_tracks : @collection.JsSet[@core.Any]
  timing_parents : @collection.JsMap[@core.Any, Set[String]]
  audio : @collection.JsSet[@core.Any]
  tracks : @collection.JsSet[@core.Any]
  objects : @collection.JsSet[@core.Any]
  compositions : @collection.JsSet[@core.Any]
  dependent_tracks : @collection.JsSet[@core.Any]
  revived_compositions : @collection.JsSet[@core.Any]
  order_entries : @collection.JsMap[@core.Any, Set[String]]
}

///|
fn empty_creations() -> CreationPlan {
  {
    roots: @collection.JsSet::new(),
    containers: @collection.JsSet::new(),
    activated_tracks: @collection.JsSet::new(),
    timing_parents: @collection.JsMap::new(),
    audio: @collection.JsSet::new(),
    tracks: @collection.JsSet::new(),
    objects: @collection.JsSet::new(),
    compositions: @collection.JsSet::new(),
    dependent_tracks: @collection.JsSet::new(),
    revived_compositions: @collection.JsSet::new(),
    order_entries: @collection.JsMap::new(),
  }
}

///|
fn Session::added(
  self : Session,
  action : @core.Any,
  value : @core.Any,
) -> Bool {
  self.is_map(value) &&
  !@core.is_nullish(value._get("_item")) &&
  self.deleted(action._get("insertions"), value._get("_item"))
}

///|
fn Session::protect_object(
  self : Session,
  plan : CreationPlan,
  action : @core.Any,
  scene : @core.Any,
  id : String,
) -> Unit {
  let objects = get(scene, "objects")
  if !self.is_map(objects) || self.added(action, objects) {
    return
  }
  let object = get(objects, id)
  if !self.added(action, object) {
    return
  }
  plan.objects.add(object) |> ignore
  plan.roots.add(object) |> ignore
  // Identity, all states and all tracks are one creation. Retaining only a
  // touched leaf would orphan an animation or discard its rendering defaults.
  for
    (collection, field) in [
      ("compositions", "states"),
      ("transitions", "tracks"),
    ] {
    let parents = get(scene, collection)
    if !self.is_map(parents) {
      continue
    }
    for parent in values(parents) {
      if !self.is_map(parent) {
        continue
      }
      let entries = get(parent, field)
      if !self.is_map(entries) {
        continue
      }
      let value = get(entries, id)
      if !self.is_map(value) {
        continue
      }
      plan.roots.add(value) |> ignore
      if field == "tracks" {
        plan.dependent_tracks.add(value) |> ignore
        if !self.added(action, entries) && self.added(action, value) {
          plan.tracks.add(value) |> ignore
        }
      }
    }
  }
}

///|
fn Session::shared_creations(
  self : Session,
  action : @core.Any,
) -> CreationPlan {
  let plan = empty_creations()
  let scenes = get(self.root, "scenes")
  if @core.is_nullish(action) || !self.is_map(scenes) {
    return plan
  }
  for scene in values(scenes) {
    if !self.is_map(scene) {
      continue
    }
    let audio = get(scene, "audioTracks")
    if !self.added(action, scene) && self.is_map(audio) {
      for track in values(audio) {
        if self.added(action, track) && self.peer_audio.has(track) {
          plan.audio.add(track) |> ignore
          plan.roots.add(track) |> ignore
          if self.added(action, audio) {
            plan.containers.add(audio) |> ignore
          }
        }
      }
    }
    let objects = get(scene, "objects")
    if self.is_map(objects) && !self.added(action, objects) {
      for id in keys(objects) {
        let object = get(objects, id)
        if self.is_map(object) && self.peer_objects.has(object) {
          self.protect_object(plan, action, scene, id)
        }
      }
    }
    let transitions = get(scene, "transitions")
    if !self.is_map(transitions) {
      continue
    }
    for transition in values(transitions) {
      if !self.is_map(transition) {
        continue
      }
      let tracks = get(transition, "tracks")
      if !self.is_map(tracks) ||
        @core.is_nullish(tracks._get("_item")) ||
        self.added(action, tracks) {
        continue
      }
      for track in values(tracks) {
        if !self.is_map(track) {
          continue
        }
        if !self.added(action, track) {
          for key in timing_keys() {
            let timing = get(track, key)
            if self.added(action, timing) &&
              self.peer_timings.has(timing) &&
              @core.is_nullish(self.field_after_undo(action, track, key)) {
              let fields = match plan.timing_parents.get(track) {
                Some(fields) => fields
                None => Set([])
              }
              fields.add(key)
              plan.timing_parents.set(track, fields) |> ignore
              plan.roots.add(timing) |> ignore
              plan.dependent_tracks.add(track) |> ignore
              plan.tracks.add(track) |> ignore
            }
          }
        }
        let activation = get(track._get("_map"), "implicit")
        let promoted = @core.equal(get(track, "implicit"), @core.any(false)) &&
          @core.equal(
            self.field_after_undo(action, track, "implicit"),
            @core.any(true),
          ) &&
          !@core.is_nullish(activation) &&
          (match self.peer_activations.get(track) {
            Some(edits) => edits.has(activation)
            None => false
          })
        if promoted {
          plan.activated_tracks.add(track) |> ignore
        }
        if promoted ||
          (self.added(action, track) && self.peer_tracks.has(track)) {
          plan.tracks.add(track) |> ignore
          plan.dependent_tracks.add(track) |> ignore
          plan.roots.add(track) |> ignore
        }
      }
    }
    self.protect_composition_batch(plan, action, scene, transitions)
  }
  plan
}

///|
fn Session::protect_composition_batch(
  self : Session,
  plan : CreationPlan,
  action : @core.Any,
  scene : @core.Any,
  transitions : @core.Any,
) -> Unit {
  let compositions = get(scene, "compositions")
  let order = get(scene, "compositionOrder")
  if !self.is_map(compositions) ||
    self.added(action, compositions) ||
    !self.is_array(order) {
    return
  }
  let created : Map[String, @core.Any] = Map([])
  for id in keys(compositions) {
    let composition = get(compositions, id)
    if self.added(action, composition) {
      created[id] = composition
    }
  }
  if created.is_empty() {
    return
  }
  let batch = @collection.JsSet::new()
  let mut retain = false
  for composition in created.values() {
    if self.peer_compositions.has(composition) {
      retain = true
    }
    let states = get(composition, "states")
    if self.is_map(states) &&
      values(states)
      .iter()
      .any(fn(state) { self.is_map(state) && plan.roots.has(state) }) {
      retain = true
    }
  }
  for transition in values(transitions) {
    if !self.is_map(transition) {
      continue
    }
    if self.added(action, transition) {
      if created.contains(string_value(get(transition, "fromId"))) ||
        created.contains(string_value(get(transition, "toId"))) {
        batch.add(transition) |> ignore
        if self.peer_transitions.has(transition) {
          retain = true
        }
      }
    } else {
      // Local reference changes will themselves Undo. Inspect what remains.
      let from = self.field_after_undo(action, transition, "fromId")
      let to = self.field_after_undo(action, transition, "toId")
      if created.contains(string_value(from)) ||
        created.contains(string_value(to)) {
        retain = true
      }
    }
  }
  if !retain {
    return
  }
  let ids : Set[String] = Set([])
  for id in created.keys() {
    ids.add(id)
  }
  plan.order_entries.set(order, ids) |> ignore
  for composition in created.values() {
    plan.compositions.add(composition) |> ignore
    plan.roots.add(composition) |> ignore
    let states = get(composition, "states")
    if self.is_map(states) {
      for id in keys(states) {
        self.protect_object(plan, action, scene, id)
      }
    }
  }
  batch.forEach(fn(transition) {
    plan.roots.add(transition) |> ignore
    let tracks = get(transition, "tracks")
    if self.is_map(tracks) {
      for id in keys(tracks) {
        self.protect_object(plan, action, scene, id)
        let track = get(tracks, id)
        if self.is_map(track) {
          plan.roots.add(track) |> ignore
          plan.dependent_tracks.add(track) |> ignore
          if self.added(action, track) {
            plan.tracks.add(track) |> ignore
          }
        }
      }
    }
    let source = get(compositions, string_value(get(transition, "fromId")))
    if self.is_map(source) &&
      !self.added(action, source) &&
      !@core.equal(get(source, "deleted"), @core.any(true)) &&
      @core.equal(
        self.field_after_undo(action, source, "deleted"),
        @core.any(true),
      ) {
      plan.revived_compositions.add(source) |> ignore
    }
  })
}

///|
fn CreationPlan::track_count(self : CreationPlan) -> Int {
  let mut count = 0
  self.tracks.forEach(fn(track) {
    if !@core.equal(get(track, "implicit"), @core.any(true)) ||
      timing_keys().iter().any(fn(key) { !@core.is_nullish(get(track, key)) }) {
      count += 1
    }
  })
  count
}
