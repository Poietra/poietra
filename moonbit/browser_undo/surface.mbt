///|
fn compatible_surface_expressions(
  kind : @core.Any,
  x : @core.Any,
  y : @core.Any,
) -> Bool {
  if @core.equal(kind, @core.any("heightfield")) {
    return true
  }
  if !@core.equal(kind, @core.any("parametric")) ||
    @core.typeof_(x) != "string" ||
    @core.typeof_(y) != "string" {
    return false
  }
  try {
    @math_plot.prepare_surface(x.cast()) |> ignore
    @math_plot.prepare_surface(y.cast()) |> ignore
    true
  } catch {
    _ => false
  }
}

///|
/// Keep peer-dependent bounds, visible modes and parametric expressions valid
/// through selective Undo. Camera, coefficients and unrelated styles still undo.
fn Session::protect_surface(
  self : Session,
  plan : CreationPlan,
  action : @core.Any,
) -> Unit {
  let scenes = get(self.root, "scenes")
  if !self.is_map(scenes) {
    return
  }
  for scene in values(scenes) {
    let compositions = get(scene, "compositions")
    if !self.is_map(compositions) {
      continue
    }
    for composition in values(compositions) {
      let states = get(composition, "states")
      if !self.is_map(states) {
        continue
      }
      for state in values(states) {
        let surface = get(state, "surface")
        if !self.is_map(surface) ||
          self.added(action, surface) ||
          plan.roots.has(state) {
          continue
        }
        let fields = Set([])
        for (low, high) in [("uMin", "uMax"), ("vMin", "vMax")] {
          if ordered_range(get(surface, low), get(surface, high)) &&
            !ordered_range(
              self.field_after_step(action, surface, low),
              self.field_after_step(action, surface, high),
            ) {
            fields.add(low)
            fields.add(high)
          }
        }
        let shown = fn(fill, wire) {
          @core.equal(fill, @core.any(true)) ||
          @core.equal(wire, @core.any(true))
        }
        if shown(get(surface, "filled"), get(surface, "wireframe")) &&
          !shown(
            self.field_after_step(action, surface, "filled"),
            self.field_after_step(action, surface, "wireframe"),
          ) {
          fields.add("filled")
          fields.add("wireframe")
        }
        let kind = get(surface, "kind")
        let x = get(surface, "xExpression")
        let y = get(surface, "yExpression")
        let next_kind = self.field_after_step(action, surface, "kind")
        let next_x = self.field_after_step(action, surface, "xExpression")
        let next_y = self.field_after_step(action, surface, "yExpression")
        if compatible_surface_expressions(kind, x, y) &&
          !compatible_surface_expressions(next_kind, next_x, next_y) {
          if compatible_surface_expressions(kind, next_x, next_y) {
            fields.add("kind")
          } else {
            fields.add("xExpression")
            fields.add("yExpression")
          }
        }
        if !fields.is_empty() {
          retain_geometry_fields(plan, surface, fields.to_array())
          plan.geometry_elements.add(surface) |> ignore
        }
      }
    }
  }
}
