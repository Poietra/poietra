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
  let project = store._call("project", [])
  let order : FixedArray[String] = project._get("sceneOrder").cast()
  if order.length() >= 100 {
    @core.throw_error("Scene は 100 件まで追加できます。")
    return ""
  }
  let id = @boundary.new_id("scene")
  let value = @boundary.make_blank_scene(
    id,
    "Scene " + (order.length() + 1).to_string(),
  )
  captured_transaction(store, fn() {
    if !order.is_empty() {
      let survivor = shared(store, ["scenes", order[0]])
      if is_shared_map(store, survivor) &&
        @core.equal(
          survivor._call("get", [@core.any("deleted")]),
          @core.any(true),
        ) {
        survivor._call("set", [@core.any("deleted"), @core.any(false)])
        |> ignore
      }
    }
    edit(store, [change(["scenes", id], value)])
    shared(store, ["sceneOrder"])._call("push", [
      @core.any(([id] : FixedArray[String])),
    ])
    |> ignore
  })
  id
}

///|
pub fn add_composition(store : @core.Any, scene_id : String) -> String {
  let scene = current_scene(store, scene_id)
  let order : FixedArray[String] = scene._get("compositionOrder").cast()
  if order.length() >= 100 {
    @core.throw_error("Composition は 100 件まで追加できます。")
    return ""
  }
  let last = if order.is_empty() {
    @core.undefined()
  } else {
    scene._get("compositions")._get(order[order.length() - 1])
  }
  let id = @boundary.new_id("comp")
  let tid = @boundary.new_id("transition")
  let colors : FixedArray[String] = store._get("runtime")._get("colors").cast()
  let states = if truthy(last) {
    last._get("states")
  } else {
    @core.new_object()
  }
  // to_shared copies each state into fresh native maps. Immutable snapshots do
  // not need an intermediate structuredClone of the whole Composition.
  let changes = [
    change(
      ["scenes", scene_id, "compositions", id],
      record([
        ("id", @core.any(id)),
        ("name", @core.any("Composition " + (order.length() + 1).to_string())),
        ("duration", @core.any(1000.0)),
        ("accent", @core.any(colors[order.length() % colors.length()])),
        ("states", states),
      ]),
    ),
  ]
  if truthy(last) {
    let ids = @core.object_keys(scene._get("objects"))
    changes.push(
      change(
        ["scenes", scene_id, "transitions", tid],
        record([
          ("id", @core.any(tid)),
          ("fromId", last._get("id")),
          ("toId", @core.any(id)),
          ("duration", @core.any(800.0)),
          (
            "tracks",
            @boundary.implicit_tracks(FixedArray::from_array(ids[:]), 800.0),
          ),
        ]),
      ),
    )
  }
  captured_transaction(store, fn() {
    if truthy(last) {
      let source = shared(store, [
        "scenes",
        scene_id,
        "compositions",
        last._get("id").cast(),
      ])
      if is_shared_map(store, source) &&
        @core.equal(
          source._call("get", [@core.any("deleted")]),
          @core.any(true),
        ) {
        source._call("set", [@core.any("deleted"), @core.any(false)]) |> ignore
      }
    }
    @boundary.apply_changes(
      store._get("doc"),
      FixedArray::from_array(changes[:]),
      @core.any("poietra-local"),
      host(store),
    )
    shared(store, ["scenes", scene_id, "compositionOrder"])._call("push", [
      @core.any(([id] : FixedArray[String])),
    ])
    |> ignore
  })
  id
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
