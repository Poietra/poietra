///|
#external
priv type StageStore

///|
#external
priv type StageRenderer

///|
#external
priv type StageScene

///|
priv struct StageBinding {
  store : StageStore
  renderer : StageRenderer
  scene_id : String
  composition_id : String
}

///|
/// Keep the shared native snapshot intact. Only requested object metadata,
/// coordinates or paths cross into gesture logic; never decode a whole Scene.
priv struct StageSnapshot {
  scene : StageScene
  composition_id : String
}

///|
fn native_stage_binding(
  store : @core.Any,
  renderer : @core.Any,
  scene_id : String,
  composition_id : String,
) -> StageBinding {
  { store: store.cast(), renderer: renderer.cast(), scene_id, composition_id, }
}

///|
fn StageBinding::current(self : StageBinding) -> StageSnapshot? {
  let scene = @core.any(self.store)
    ._call("project", [])
    ._get("scenes")
    ._get(self.scene_id)
  if !truthy(scene) ||
    !truthy(scene._get("compositions")._get(self.composition_id)) {
    None
  } else {
    Some({ scene: scene.cast(), composition_id: self.composition_id, })
  }
}

///|
fn StageBinding::history(self : StageBinding) -> GestureHistory {
  native_gesture_history(@core.any(self.store))
}

///|
fn StageSnapshot::object(self : StageSnapshot, id : String) -> StageObjectInfo? {
  let object = @core.any(self.scene)._get("objects")._get(id)
  if truthy(object) {
    Some({
      kind: @boundary.read_object_kind(object._get("kind")),
      locked: truthy(object._get("locked")),
    })
  } else {
    None
  }
}

///|
fn StageBinding::transform_start(
  self : StageBinding,
  snapshot : StageSnapshot,
  id : String,
) -> (@scene.ObjectState, Double, Double)? {
  let scene = @core.any(snapshot.scene)
  let stored = @boundary.state_for(scene, snapshot.composition_id, id)
  if !truthy(stored) || !truthy(stored._get("visible")) {
    return None
  }
  let state = @boundary.read_object_state(stored)
  let bounds = stage_bounds(
    @core.any(self.renderer)._call("objectBounds", [
      host_record({
        "object": scene._get("objects")._get(id),
        "state": stored,
        "writeProgress": @core.any(1),
        "order": @core.any("together"),
      }),
    ]),
  )
  let stroke = state.strokeWidth.max(0.0)
  Some((state, bounds.width - stroke, bounds.height - stroke))
}

///|
fn StageBinding::linked_ids(
  self : StageBinding,
  ids : Array[String],
) -> FixedArray[String] {
  @core.any(self.store)
  ._call("linkedIds", [@core.any(self.scene_id), @core.any(host_array(ids))])
  .cast()
}

///|
fn StageSnapshot::positions(
  self : StageSnapshot,
  ids : FixedArray[String],
) -> Map[String, @scene.Point] {
  let positions : Map[String, @scene.Point] = Map([])
  for id in ids {
    let state = @boundary.state_for(
      @core.any(self.scene),
      self.composition_id,
      id,
    )
    if truthy(state) && truthy(state._get("visible")) {
      positions[id] = { x: state._get("x").cast(), y: state._get("y").cast(), }
    }
  }
  positions
}

///|
fn StageSnapshot::has_path(
  self : StageSnapshot,
  id : String,
  transition_id : String?,
) -> Bool {
  let scene = @core.any(self.scene)
  let value = match transition_id {
    Some(transition_id) => {
      let transition = scene._get("transitions")._get(transition_id)
      if !truthy(transition) {
        return false
      }
      transition._get("tracks")._get(id)
    }
    None => @boundary.state_for(scene, self.composition_id, id)
  }
  truthy(value) && truthy(value._get("path"))
}

///|
fn StageSnapshot::parent_matrix(
  self : StageSnapshot,
  id : String,
) -> @scene.Affine {
  @boundary.parent_matrix(@core.any(self.scene), self.composition_id, id)
}

///|
fn StageSnapshot::object_matrix(
  self : StageSnapshot,
  id : String,
) -> @scene.Affine {
  @boundary.object_matrix(@core.any(self.scene), self.composition_id, id)
}

///|
fn StageBinding::update_state(
  self : StageBinding,
  id : String,
  patch : @core.Any,
) -> Unit {
  @core.any(self.store)._call("updateState", [
    @core.any(self.scene_id),
    @core.any(self.composition_id),
    @core.any(id),
    patch,
    @core.any(false),
  ])
  |> ignore
}

///|
fn StageBinding::set_transform(
  self : StageBinding,
  id : String,
  value : StageTransformValue,
) -> Unit {
  let patch = match value {
    Rotation(rotation) => host_record({ "rotation": @core.any(rotation) })
    Size(size) => {
      let patch = host_record({
        "x": @core.any(size.x),
        "y": @core.any(size.y),
        "width": @core.any(size.width),
        "height": @core.any(size.height),
      })
      if size.font_size is Some(font_size) {
        patch._set("fontSize", @core.any(font_size))
      }
      patch
    }
  }
  self.update_state(id, patch)
}

///|
/// Write only the dragged point's coordinates. Replacing path/c1/c2 maps
/// detaches concurrent point edits and lets gesture Undo erase a peer's work.
fn StageBinding::set_path_point(
  self : StageBinding,
  id : String,
  transition_id : String?,
  handle : @editor.CurvePoint,
  point : @scene.Point,
) -> Unit {
  let base : FixedArray[String] = match transition_id {
    None =>
      [
        "scenes",
        self.scene_id,
        "compositions",
        self.composition_id,
        "states",
        id,
        "path",
      ]
    Some(transition_id) =>
      [
        "scenes",
        self.scene_id,
        "transitions",
        transition_id,
        "tracks",
        id,
        "path",
      ]
  }
  let point_path = FixedArray::makei(base.length() + 1, fn(i) {
    if i < base.length() {
      base[i]
    } else {
      match handle {
        First => "c1"
        Second => "c2"
      }
    }
  })
  let changes = @boundary.changes_for(point_path, stage_point(point))
  @core.any(self.store)._call("edit", [@core.any(changes), @core.any(false)])
  |> ignore
}

///|
fn StageBinding::translate(
  self : StageBinding,
  positions : Map[String, @scene.Point],
  delta : @scene.Point,
) -> Unit {
  let targets = @core.new_object()
  for id, position in positions {
    targets._set(id, stage_point(position))
  }
  @core.any(self.store)._call("translate", [
    @core.any(self.scene_id),
    @core.any(self.composition_id),
    targets,
    @core.any(delta.x),
    @core.any(delta.y),
  ])
  |> ignore
}

///|
fn StageBinding::add_object(
  self : StageBinding,
  kind : @scene.ObjectKind,
  state : @scene.ObjectState,
) -> String {
  @core.any(self.store)
  ._call("addObject", [
    @core.any(self.scene_id),
    @core.any(self.composition_id),
    @core.any(@scene.object_kind_name(kind)),
    @boundary.write_object_state(state),
  ])
  .cast()
}

///|
fn StageBinding::presence(self : StageBinding, point : @scene.Point?) -> Unit {
  let patch = match point {
    Some(point) =>
      host_record({
        "sceneId": @core.any(self.scene_id),
        "compositionId": @core.any(self.composition_id),
        "cursor": stage_point(point),
      })
    None => host_record({ "cursor": @core.null() })
  }
  @core.any(self.store)._call("presence", [patch]) |> ignore
}
