///|
fn read_source(
  original : @core.Any,
  doc : @core.Any,
  base : Array[String],
  raw_compositions : @core.Any,
  yjs : @core.Any,
) -> @plan.Source {
  let native_objects = original._get("objects")
  let objects = Map([])
  for id in @core.object_keys(native_objects) {
    objects[id] = @boundary.read_scene_object(native_objects._get(id))
  }
  let native_compositions = original._get("compositions")
  let compositions = Map([])
  for id in @core.object_keys(native_compositions) {
    let composition = native_compositions._get(id)
    compositions[id] = @plan.CompositionInfo::{
      id: composition._get("id").cast(),
      name: composition._get("name").cast(),
      duration: composition._get("duration").cast(),
      accent: composition._get("accent").cast(),
      state_ids: @core.object_keys(composition._get("states")),
    }
  }
  let native_transitions = original._get("transitions")
  let transitions = Map([])
  for id in @core.object_keys(native_transitions) {
    let transition = native_transitions._get(id)
    transitions[id] = @plan.TransitionInfo::{
      id: transition._get("id").cast(),
      from_id: transition._get("fromId").cast(),
      to_id: transition._get("toId").cast(),
      duration: transition._get("duration").cast(),
      track_ids: @core.object_keys(transition._get("tracks")),
    }
  }
  let state_cache : Map[(String, String), @scene.ObjectState?] = Map([])
  let track_cache : Map[(String, String), @scene.Track?] = Map([])
  let state = fn(cid : String, oid : String) {
    let key = (cid, oid)
    if state_cache.get(key) is Some(value) {
      return value
    }
    // Reparenting also visits retained Compositions so restoring one with
    // Undo cannot resurrect coordinates from the previous parent space.
    let native_state = if owns(native_compositions, cid) {
      native_compositions._get(cid)._get("states")._get(oid)
    } else {
      value(doc, base + ["compositions", cid, "states", oid], yjs)
    }
    let result = if @core.is_nullish(native_state) {
      None
    } else {
      Some(@boundary.read_object_state(native_state))
    }
    state_cache[key] = result
    result
  }
  let track = fn(tid : String, oid : String) {
    let key = (tid, oid)
    if track_cache.get(key) is Some(value) {
      return value
    }
    let transition = native_transitions._get(tid)
    let result = if !owns(native_transitions, tid) ||
      !owns(transition._get("tracks"), oid) {
      None
    } else {
      Some(@boundary.read_track(transition._get("tracks")._get(oid)))
    }
    track_cache[key] = result
    result
  }
  let raw_ids : Array[String] = []
  raw_compositions._call("forEach", [
    @core.any(fn(_entry : @core.Any, id : String) { raw_ids.push(id) }),
  ])
  |> ignore
  let deleted = Set([])
  for id in raw_ids {
    if same_identity(
        value(doc, base + ["compositions", id, "deleted"], yjs),
        @core.any(true),
      ) {
      deleted.add(id)
    }
  }
  {
    objects,
    compositions,
    transitions,
    state,
    track,
    order: string_array(original._get("compositionOrder")),
    raw_composition_ids: raw_ids,
    deleted_compositions: deleted,
  }
}
