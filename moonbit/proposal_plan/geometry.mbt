///|
fn diagram_element_fields(element : DiagramElement) -> Map[String, Value] {
  match element {
    PointElement(p) =>
      {
        "kind": ScalarValue(Text(@scene.geometry_point_kind_name(p.kind))),
        "x": ScalarValue(Number(p.x)),
        "y": ScalarValue(Number(p.y)),
        "from": ParentValue(p.from),
        "to": ParentValue(p.to),
        "label": ScalarValue(Text(p.label)),
        "deleted": ScalarValue(Boolean(p.deleted == Some(true))),
      }
    VectorElement(v) =>
      {
        "from": ScalarValue(Text(v.from)),
        "to": ScalarValue(Text(v.to)),
        "label": ScalarValue(Text(v.label)),
        "deleted": ScalarValue(Boolean(v.deleted == Some(true))),
      }
    AngleElement(v) =>
      {
        "from": ScalarValue(Text(v.from)),
        "vertex": ScalarValue(Text(v.vertex)),
        "to": ScalarValue(Text(v.to)),
        "label": ScalarValue(Text(v.label)),
        "deleted": ScalarValue(Boolean(v.deleted == Some(true))),
      }
  }
}

///|
fn diagram_element(
  definition : @scene.GeometryDefinition,
  collection : String,
  id : String,
) -> DiagramElement? {
  match collection {
    "points" => definition.points.get(id).map(fn(value) { PointElement(value) })
    "vectors" =>
      definition.vectors.get(id).map(fn(value) { VectorElement(value) })
    "angles" => definition.angles.get(id).map(fn(value) { AngleElement(value) })
    _ => None
  }
}

///|
fn Compiler::edit_geometry(
  self : Compiler,
  cid : String,
  oid : String,
  collection : String,
  id : String,
  element : DiagramElement?,
) -> Unit raise CompileError {
  let cid = self.resolve(cid, CompositionRef)
  let oid = self.resolve(oid, ObjectRef)
  let object = self.object(oid)
  self.composition(cid) |> ignore
  if object.kind != Geometry ||
    !["points", "vectors", "angles"].contains(collection) ||
    id.is_empty() ||
    id.length() > 80 {
    raise CompileError("数学図の編集対象が不正です。")
  }
  let state = self.state(cid, oid).unwrap_or(@scene.default_state(Geometry))
  let definition = state.geometry.unwrap_or(@scene.default_geometry())
  let previous = diagram_element(definition, collection, id)
  let next = match (collection, element) {
    ("points", Some(PointElement(p))) =>
      PointElement({ ..p, deleted: Some(false), })
    ("vectors", Some(VectorElement(v))) =>
      VectorElement({ ..v, deleted: Some(false), })
    ("angles", Some(AngleElement(v))) =>
      AngleElement({ ..v, deleted: Some(false), })
    (_, None) =>
      match previous {
        Some(PointElement(p)) => PointElement({ ..p, deleted: Some(true), })
        Some(VectorElement(v)) => VectorElement({ ..v, deleted: Some(true), })
        Some(AngleElement(v)) => AngleElement({ ..v, deleted: Some(true), })
        None => raise CompileError("削除する要素がありません。")
      }
    _ =>
      raise CompileError(
        "要素とコレクションの種類が一致しません。",
      )
  }
  let definition = match next {
    PointElement(p) => {
      let points = definition.points.copy()
      points[id] = p
      { ..definition, points, }
    }
    VectorElement(v) => {
      let vectors = definition.vectors.copy()
      vectors[id] = v
      { ..definition, vectors, }
    }
    AngleElement(v) => {
      let angles = definition.angles.copy()
      angles[id] = v
      { ..definition, angles, }
    }
  }
  self.set_state(cid, oid, { ..state, geometry: Some(definition), })
  if self.created.contains(oid) || self.appended.contains(cid) {
    return
  }
  let base = ["compositions", cid, "states", oid, "geometry"]
  self.depend(base + ["version"])
  let path = base + [collection, id]
  match previous {
    None => {
      self.depend(base + [collection])
      self.emit(
        path,
        match next {
          PointElement(p) => GeometryPointValue(p)
          VectorElement(v) => GeometryVectorValue(v)
          AngleElement(v) => GeometryAngleValue(v)
        },
      )
    }
    Some(previous) => {
      let old_fields = diagram_element_fields(previous)
      for key, value in diagram_element_fields(next) {
        // Compare the scalar leaf, including absent references and tombstones.
        let changed = match (old_fields.get(key), value) {
          (Some(ScalarValue(a)), ScalarValue(b)) =>
            match (a, b) {
              (Number(a), Number(b)) => a != b
              (Text(a), Text(b)) => a != b
              (Boolean(a), Boolean(b)) => a != b
              _ => true
            }
          (Some(ParentValue(a)), ParentValue(b)) => a != b
          _ => true
        }
        if changed {
          self.emit(path + [key], value)
        }
      }
    }
  }
  // Coordinate/label edits need no unrelated point guards. Structural edits
  // depend on topology, but allow peer coordinate changes on referenced points.
  let structural = element is None ||
    previous is None ||
    ({
      let old = diagram_element_fields(previous.unwrap())
      let updated = diagram_element_fields(next)
      ["kind", "from", "to", "vertex", "deleted"].any(fn(key) {
        match (old.get(key), updated.get(key)) {
          (Some(ScalarValue(Text(a))), Some(ScalarValue(Text(b)))) => a != b
          (Some(ScalarValue(Boolean(a))), Some(ScalarValue(Boolean(b)))) =>
            a != b
          (Some(ParentValue(a)), Some(ParentValue(b))) => a != b
          (None, None) => false
          _ => true
        }
      })
    })
  if structural {
    if element is None {
      self.depend(base)
    }
    for point_id in definition.points.keys() {
      for key in ["kind", "from", "to", "deleted"] {
        self.depend(base + ["points", point_id, key])
      }
    }
  }
}
