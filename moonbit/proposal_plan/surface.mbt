///|
fn surface_fields(d : @scene.SurfaceDefinition) -> Map[String, Value] {
  {
    "version": ScalarValue(Number(d.version.to_double())),
    "kind": ScalarValue(Text(@scene.surface_kind_name(d.kind))),
    "xExpression": ScalarValue(Text(d.xExpression)),
    "yExpression": ScalarValue(Text(d.yExpression)),
    "zExpression": ScalarValue(Text(d.zExpression)),
    "uMin": ScalarValue(Number(d.uMin)),
    "uMax": ScalarValue(Number(d.uMax)),
    "vMin": ScalarValue(Number(d.vMin)),
    "vMax": ScalarValue(Number(d.vMax)),
    "a": ScalarValue(Number(d.a)),
    "b": ScalarValue(Number(d.b)),
    "c": ScalarValue(Number(d.c)),
    "yaw": ScalarValue(Number(d.yaw)),
    "pitch": ScalarValue(Number(d.pitch)),
    "zoom": ScalarValue(Number(d.zoom)),
    "steps": ScalarValue(Number(d.steps.to_double())),
    "filled": ScalarValue(Boolean(d.filled)),
    "wireframe": ScalarValue(Boolean(d.wireframe)),
    "axes": ScalarValue(Boolean(d.axes)),
  }
}

///|
fn Compiler::edit_surface(
  self : Compiler,
  cid : String,
  oid : String,
  definition : @scene.SurfaceDefinition,
) -> Unit raise CompileError {
  let cid = self.resolve(cid, CompositionRef)
  let oid = self.resolve(oid, ObjectRef)
  if self.object(oid).kind != Surface {
    raise CompileError(
      "曲面を編集できるのは3D曲面オブジェクトだけです。",
    )
  }
  self.composition(cid) |> ignore
  if @scene.surface_validation_error(definition) is Some(message) {
    raise CompileError(message)
  }
  let state = self.state(cid, oid).unwrap_or(@scene.default_state(Surface))
  let previous = state.surface.unwrap_or(@scene.default_surface())
  self.set_state(cid, oid, { ..state, surface: Some(definition), })
  if self.created.contains(oid) || self.appended.contains(cid) {
    return
  }
  let base = ["compositions", cid, "states", oid, "surface"]
  let old = surface_fields(previous)
  let next = surface_fields(definition)
  self.depend(base + ["version"])
  for key, value in next {
    if math_value_changed(old.get(key), Some(value)) {
      self.emit(base + [key], value)
      // Keep coupled range and visibility constraints valid after peer edits.
      let coupled = match key {
        "uMin" => ["uMax"]
        "uMax" => ["uMin"]
        "vMin" => ["vMax"]
        "vMax" => ["vMin"]
        "filled" => ["wireframe"]
        "wireframe" => ["filled"]
        "kind" => ["xExpression", "yExpression", "zExpression"]
        "xExpression" | "yExpression" => ["kind"]
        _ => []
      }
      for field in coupled {
        self.depend(base + [field])
      }
    }
  }
}
