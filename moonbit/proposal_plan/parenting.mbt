///|
let transform_fields : ReadOnlyArray[String] = [
  "x", "y", "rotation", "anchorX", "anchorY", "scaleX", "scaleY", "shear",
]

///|
fn Compiler::guard_transform(
  self : Compiler,
  cid : String,
  oid : String,
  state : @scene.ObjectState?,
) -> Unit raise CompileError {
  if self.created.contains(oid) || self.appended.contains(cid) {
    return
  }
  let path = ["compositions", cid, "states", oid]
  match state {
    None => self.depend(path)
    Some(_) =>
      for field in transform_fields {
        self.depend(path + [field])
      }
  }
}

///|
fn Compiler::write_transform(
  self : Compiler,
  cid : String,
  oid : String,
  before : @scene.ObjectState,
  after : @scene.ObjectState,
) -> Unit {
  self.set_state(cid, oid, after)
  if self.created.contains(oid) || self.appended.contains(cid) {
    return
  }
  let old = [
    before.x,
    before.y,
    before.rotation,
    before.anchorX.unwrap_or(0.0),
    before.anchorY.unwrap_or(0.0),
    before.scaleX.unwrap_or(1.0),
    before.scaleY.unwrap_or(1.0),
    before.shear.unwrap_or(0.0),
  ]
  let next = [
    after.x,
    after.y,
    after.rotation,
    after.anchorX.unwrap_or(0.0),
    after.anchorY.unwrap_or(0.0),
    after.scaleX.unwrap_or(1.0),
    after.scaleY.unwrap_or(1.0),
    after.shear.unwrap_or(0.0),
  ]
  for index, name in transform_fields {
    if old[index] != next[index] {
      self.emit(
        ["compositions", cid, "states", oid, name],
        ScalarValue(Number(next[index])),
      )
    }
  }
}

///|
fn Compiler::reparent(
  self : Compiler,
  reference : String,
  parent_reference : String?,
) -> Unit raise CompileError {
  let oid = self.resolve(reference, ObjectRef)
  let object = self.object(oid)
  let parent = parent_reference.map(id => self.resolve(id, ObjectRef))
  if object.parentId == parent {
    return
  }
  let dependencies : Set[String] = Set([])
  for start in [Some(oid), parent] {
    let mut cursor = start
    while cursor is Some(id) && !dependencies.contains(id) {
      dependencies.add(id)
      let target = match self.objects.get(id) {
        None =>
          raise CompileError("親オブジェクトが見つかりません。")
        Some(target) => target
      }
      if !self.created.contains(id) {
        self.depend(["objects", id, "id"])
        self.depend(["objects", id, "parentId"])
      }
      cursor = target.parentId
    }
  }
  let compositions = Map([])
  for cid in self.source.raw_composition_ids + self.appended {
    let states = Map([])
    for id in dependencies {
      let state = self.state(cid, id)
      self.guard_transform(cid, id, state)
      if state is Some(value) {
        states[id] = value
      }
    }
    compositions[cid] = {
      ..@scene.empty_composition(cid, cid, 0.0, "#ffffff"),
      states,
    }
  }
  let scene = {
    ..@scene.blank_scene("plan", "plan"),
    objects: self.objects,
    compositions,
  }
  let plan = match @editor.plan_reparent(scene, oid, parent) {
    Err(message) => raise CompileError(message)
    Ok(plan) => plan
  }
  self.objects[oid] = { ..object, parentId: parent, }
  for (cid, next) in plan.states {
    self.write_transform(cid, oid, self.state(cid, oid).unwrap(), next)
  }
  if !self.created.contains(oid) {
    self.emit(["objects", oid, "parentId"], ParentValue(parent))
  }
}

///|
fn Compiler::anchor(
  self : Compiler,
  cid : String,
  oid : String,
  x : Double,
  y : Double,
) -> Unit raise CompileError {
  let cid = self.resolve(cid, CompositionRef)
  let oid = self.resolve(oid, ObjectRef)
  self.object(oid) |> ignore
  self.composition(cid) |> ignore
  validate_state(AnchorX, Number(x), None)
  validate_state(AnchorY, Number(y), None)
  let state = self.state(cid, oid)
  self.guard_transform(cid, oid, state)
  let state = match state {
    Some(state) => state
    None =>
      raise CompileError("編集対象の状態が見つかりません。")
  }
  let next = @editor.move_anchor(state, x, y)
  if !@assets.bounded_number(next.x, -100000.0, 100000.0) ||
    !@assets.bounded_number(next.y, -100000.0, 100000.0) {
    raise CompileError(
      "アンカー変更後の座標が保存可能な範囲を超えます。",
    )
  }
  self.write_transform(cid, oid, state, next)
}
