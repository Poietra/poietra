///|
fn captured_transaction(store : @core.Any, action : () -> Unit) -> Unit {
  let result = try {
    stop_capture(store)
    defer stop_capture(store)
    @core.throwable(fn() {
      store
      ._get("doc")
      ._call("transact", [@core.any(action), @core.any("poietra-local")])
      |> ignore
    })
    Ok(())
  } catch {
    error => Err(error)
  }
  if result is Err(error) {
    @core.throw_(native_error(error))
  }
}

///|
pub fn add_scene(store : @core.Any) -> String {
  let prepared = @boundary.prepare_scene_append(
    store._get("doc"),
    store._call("project", []),
    host(store),
  )
  captured_transaction(store, prepared.publish)
  prepared.id
}

///|
pub fn add_composition(store : @core.Any, scene_id : String) -> String {
  let prepared = @boundary.prepare_composition_append(
    store._get("doc"),
    scene_id,
    current_scene(store, scene_id),
    store._get("runtime")._get("colors"),
    host(store),
  )
  captured_transaction(store, prepared.publish)
  prepared.id
}

///|
pub fn set_composition(
  store : @core.Any,
  scene_id : String,
  id : String,
  patch : @core.Any,
) -> Unit {
  edit(store, changes_for(["scenes", scene_id, "compositions", id], patch))
}

///|
pub fn apply_proposal(store : @core.Any, proposal : @core.Any) -> Unit {
  let result = try {
    stop_capture(store)
    defer stop_capture(store)
    @core.throwable(fn() {
      store
      ._get("runtime")
      ._call("applyProposal", [store._get("doc"), proposal])
    })
    |> ignore
    Ok(())
  } catch {
    error => Err(error)
  }
  if result is Err(error) {
    @core.throw_(native_error(error))
  }
}
