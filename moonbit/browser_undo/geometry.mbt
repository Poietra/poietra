///|
fn Session::remember_geometry_edits(
  self : Session,
  state : @core.Any,
  path : FixedArray[String],
  changed : FixedArray[String],
) -> Unit {
  if (path.length() == 6 && !changed.contains("geometry")) ||
    (path.length() > 6 && path[6] != "geometry") {
    return
  }
  let diagram = get(state, "geometry")
  if !self.is_map(diagram) {
    return
  }
  for field in ["points", "vectors", "angles"] {
    if (path.length() == 7 && !changed.contains(field)) ||
      (path.length() > 7 && path[7] != field) {
      continue
    }
    let collection = get(diagram, field)
    if !self.is_map(collection) {
      continue
    }
    let ids = if path.length() < 8 {
      keys(collection)
    } else if path.length() == 8 {
      changed
    } else {
      [path[8]]
    }
    for id in ids {
      let element = get(collection, id)
      if self.is_map(element) {
        self.peer_geometry.add(element) |> ignore
      }
    }
  }
}

///|
fn retain_geometry_fields(
  plan : CreationPlan,
  parent : @core.Any,
  fields : Array[String],
) -> Unit {
  let retained = plan.retained_fields.get(parent).unwrap_or(Set([]))
  for field in fields {
    retained.add(field)
  }
  plan.retained_fields.set(parent, retained) |> ignore
}

///|
fn geometry_protection_count(plan : CreationPlan) -> Int {
  plan.geometry_elements.size() +
  plan.retained_fields
  .values()
  .iter()
  .fold(init=0, fn(total, fields) { total + fields.size() })
}

///|
fn Session::geometry_after(
  self : Session,
  plan : CreationPlan,
  action : @core.Any,
  parent : @core.Any,
  field : String,
) -> @core.Any {
  if plan.roots.has(get(parent, field)) ||
    plan.roots.has(parent) ||
    plan.retained_fields.get(parent).unwrap_or(Set([])).contains(field) {
    get(parent, field)
  } else {
    self.field_after_step(action, parent, field)
  }
}

///|
fn Session::geometry_active(
  self : Session,
  plan : CreationPlan,
  action : @core.Any,
  element : @core.Any,
) -> Bool {
  self.is_map(element) &&
  !@core.equal(
    self.geometry_after(plan, action, element, "deleted"),
    @core.any(true),
  )
}

///|
fn Session::retain_geometry_element(
  self : Session,
  plan : CreationPlan,
  action : @core.Any,
  collection : @core.Any,
  element : @core.Any,
) -> Unit {
  plan.geometry_elements.add(element) |> ignore
  if self.added(action, element) {
    plan.roots.add(element) |> ignore
    if self.added(action, collection) {
      plan.containers.add(collection) |> ignore
    }
  } else {
    retain_geometry_fields(plan, element, ["deleted"])
  }
}

///|
/// Retain a point used by a surviving peer construction and the minimum
/// reference leaves needed to keep the one-way construction graph resolvable.
fn Session::protect_geometry(
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
        let diagram = get(state, "geometry")
        if !self.is_map(diagram) || plan.roots.has(state) {
          continue
        }
        let points = get(diagram, "points")
        if !self.is_map(points) {
          continue
        }
        for field in ["points", "vectors", "angles"] {
          let collection = get(diagram, field)
          if !self.is_map(collection) {
            continue
          }
          for element in values(collection) {
            if self.added(action, element) && self.peer_geometry.has(element) {
              self.retain_geometry_element(plan, action, collection, element)
            }
          }
        }
        for _ in 0..<(keys(points).length() + 2) {
          let before = geometry_protection_count(plan)
          for field in ["points", "vectors", "angles"] {
            let collection = get(diagram, field)
            if !self.is_map(collection) {
              continue
            }
            for id in keys(collection._get("_map")) {
              let element = self.geometry_after(plan, action, collection, id)
              if !self.geometry_active(plan, action, element) {
                continue
              }
              if field == "points" &&
                !@core.equal(
                  self.geometry_after(plan, action, element, "kind"),
                  @core.any("midpoint"),
                ) {
                continue
              }
              let references = if field == "angles" {
                ["from", "vertex", "to"]
              } else {
                ["from", "to"]
              }
              for key in references {
                let target_id = string_value(
                  self.geometry_after(plan, action, element, key),
                )
                let target = self.geometry_after(
                  plan, action, points, target_id,
                )
                if self.geometry_active(plan, action, target) {
                  continue
                }
                let current = get(points, target_id)
                if self.is_map(current) &&
                  !@core.equal(get(current, "deleted"), @core.any(true)) {
                  self.retain_geometry_element(plan, action, points, current)
                } else {
                  let current_element = get(collection, id)
                  if !self.is_map(current_element) {
                    retain_geometry_fields(plan, collection, [id])
                  } else if @core.equal(
                      get(current_element, "deleted"),
                      @core.any(true),
                    ) {
                    retain_geometry_fields(plan, current_element, ["deleted"])
                  } else {
                    retain_geometry_fields(plan, current_element, [key])
                  }
                  plan.geometry_elements.add(element) |> ignore
                }
              }
            }
          }
          let inputs : Array[@math_geometry.Input] = []
          let elements : Map[String, @core.Any] = Map([])
          for id in keys(points._get("_map")) {
            let point = self.geometry_after(plan, action, points, id)
            if !self.geometry_active(plan, action, point) {
              continue
            }
            let construction = if @core.equal(
                self.geometry_after(plan, action, point, "kind"),
                @core.any("free"),
              ) {
              let x = self.geometry_after(plan, action, point, "x")
              let y = self.geometry_after(plan, action, point, "y")
              if @core.typeof_(x) != "number" || @core.typeof_(y) != "number" {
                continue
              }
              @math_geometry.Free({ x: x.cast(), y: y.cast(), })
            } else {
              @math_geometry.Midpoint(
                string_value(self.geometry_after(plan, action, point, "from")),
                string_value(self.geometry_after(plan, action, point, "to")),
              )
            }
            inputs.push({ id, construction, })
            elements[id] = point
          }
          for id in @math_geometry.evaluate(inputs).unresolved {
            let point = elements[id]
            let changed = ["kind", "from", "to", "deleted"].filter(fn(key) {
              !@core.equal(
                get(point, key),
                self.geometry_after(plan, action, point, key),
              )
            })
            if !changed.is_empty() {
              retain_geometry_fields(plan, point, changed)
              plan.geometry_elements.add(point) |> ignore
            }
          }
          if geometry_protection_count(plan) == before {
            break
          }
        }
      }
    }
  }
}
