///|
fn ordered_range(low : @core.Any, high : @core.Any) -> Bool {
  if @core.typeof_(low) != "number" || @core.typeof_(high) != "number" {
    return false
  }
  let low : Double = low.cast()
  let high : Double = high.cast()
  !low.is_nan() &&
  !low.is_inf() &&
  !high.is_nan() &&
  !high.is_inf() &&
  high - low >= 1.0e-9
}

///|
fn compatible_graph_syntax(version : @core.Any, expression : @core.Any) -> Bool {
  if @core.typeof_(expression) != "string" {
    return false
  }
  let source : String = expression.cast()
  @core.equal(version, @core.any(2)) ||
  (@core.equal(version, @core.any(1)) && !source.contains("="))
}

///|
/// A peer may use a locally extended range. Preserve the necessary bounds if
/// Undo/Redo would invert it, while unrelated expression/style edits still undo.
/// Equations also retain the grammar needed by a surviving peer expression.
fn Session::protect_graph_ranges(
  self : Session,
  plan : CreationPlan,
  action : @core.Any,
) -> Unit {
  let scenes = get(self.root, "scenes")
  if !self.is_map(scenes) {
    return
  }
  for scene in values(scenes) {
    if !self.is_map(scene) {
      continue
    }
    let objects = get(scene, "objects")
    if !self.is_map(objects) {
      continue
    }
    let ids = keys(objects)
      .iter()
      .filter(fn(id) {
        let object = get(objects, id)
        self.is_map(object) &&
        @core.equal(get(object, "kind"), @core.any("graph"))
      })
      .to_array()
    if ids.is_empty() {
      continue
    }
    let compositions = get(scene, "compositions")
    if !self.is_map(compositions) {
      continue
    }
    for composition in values(compositions) {
      if !self.is_map(composition) {
        continue
      }
      let states = get(composition, "states")
      if !self.is_map(states) {
        continue
      }
      for id in ids {
        let state = get(states, id)
        if !self.is_map(state) {
          continue
        }
        let graph = get(state, "graph")
        if !self.is_map(graph) || self.added(action, graph) {
          continue
        }
        let fields = Set([])
        for (low, high) in [("xMin", "xMax"), ("yMin", "yMax")] {
          if ordered_range(get(graph, low), get(graph, high)) &&
            !ordered_range(
              self.field_after_step(action, graph, low),
              self.field_after_step(action, graph, high),
            ) {
            fields.add(low)
            fields.add(high)
          }
        }
        if !fields.is_empty() {
          plan.graph_ranges.add(graph) |> ignore
        }
        let version = get(graph, "syntaxVersion")
        let expression = get(graph, "expression")
        let next_version = self.field_after_step(action, graph, "syntaxVersion")
        let next_expression = self.field_after_step(action, graph, "expression")
        if compatible_graph_syntax(version, expression) &&
          !compatible_graph_syntax(next_version, next_expression) {
          if compatible_graph_syntax(version, next_expression) {
            fields.add("syntaxVersion")
          } else {
            fields.add("expression")
          }
          plan.graph_definitions.add(graph) |> ignore
        }
        if !fields.is_empty() {
          plan.retained_fields.set(graph, fields) |> ignore
        }
      }
    }
  }
}
