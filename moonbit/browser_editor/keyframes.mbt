///|
pub fn set_keyframe(
  store : @core.Any,
  scene_id : String,
  transition_id : String,
  object_id : String,
  id : String,
  patch : @core.Any,
  separate : Bool,
) -> Unit {
  guard editable_transition(store, scene_id, transition_id, object_id)
    is Some(transition) else {
    return
  }
  let track = transition._get("tracks")._get(object_id)
  if !truthy(track) || !truthy(track._get("keyframes")) {
    @core.throw_error(
      "キーフレームを準備しています。一度サーバーへ同期してから編集してください。",
    )
    return
  }
  let keys = track._get("keyframes")
  let previous = keys._get(id)
  let base = [
    "scenes", scene_id, "transitions", transition_id, "tracks", object_id, "keyframes",
    id,
  ]
  if @core.is_nullish(patch) {
    if truthy(previous) {
      edit(store, [change(base + ["deleted"], @core.any(true))], separate~)
    }
    return
  }
  let next = merge(
    if truthy(previous) {
      previous
    } else {
      @core.new_object()
    },
    patch,
  )
  @boundary.validate_keyframe(next)
  if !truthy(previous) && @core.object_keys(keys).length() >= 1024 {
    @core.throw_error(
      "1 オブジェクトの Transition に保持できるキーフレームは 1024 個までです。",
    )
    return
  }
  // Validate IDs with the same portable-file rules before constructing paths.
  if !@boundary.valid_document_id(id) {
    @core.throw_error("キーフレーム ID が無効です。")
    return
  }
  let changes = if !truthy(previous) {
    [change(base, @boundary.write_keyframe(@boundary.read_keyframe(next)))]
  } else {
    let changes = []
    for key in @core.object_keys(patch) {
      if ["at", "value", "easing", "property", "deleted"].contains(key) &&
        !@core.equal(previous._get(key), next._get(key)) {
        changes.push(change(base + [key], next._get(key)))
      }
    }
    changes
  }
  if changes.is_empty() {
    return
  }
  changes.push(change(["version"], @core.any(2)))
  edit(store, changes, separate~)
}

///|
pub fn set_parent(
  store : @core.Any,
  scene_id : String,
  id : String,
  parent : @core.Any,
) -> Unit {
  edit(
    store,
    @boundary.reparent_changes(
      @boundary.get_value(store._get("doc"), ["scenes", scene_id], host(store)),
      id,
      parent,
    ),
  )
}

///|
pub fn set_anchor(
  store : @core.Any,
  scene_id : String,
  composition_id : String,
  id : String,
  x : Double,
  y : Double,
) -> Unit {
  if x.is_nan() || y.is_nan() || x.abs() > 100000.0 || y.abs() > 100000.0 {
    @core.throw_error(
      "アンカーが編集可能な範囲を超えています。",
    )
    return
  }
  let scene = current_scene(store, scene_id)
  let state = scene
    ._get("compositions")
    ._get(composition_id)
    ._get("states")
    ._get(id)
  if !truthy(state) {
    return
  }
  let next = @editor.move_anchor(@boundary.read_object_state(state), x, y)
  if [next.x, next.y].any(fn(value) {
      value.is_nan() || value.is_inf() || value.abs() > 100000.0
    }) {
    @core.throw_error(
      "アンカー変更後の座標が保存可能な範囲を超えます。",
    )
    return
  }
  update_state(
    store,
    scene_id,
    composition_id,
    id,
    record([
      ("x", @core.any(next.x)),
      ("y", @core.any(next.y)),
      ("anchorX", @core.any(x)),
      ("anchorY", @core.any(y)),
    ]),
    true,
  )
}
