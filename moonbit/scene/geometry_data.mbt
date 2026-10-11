///|
pub(all) enum GeometryPointKind {
  FreePoint
  MidpointPoint
} derive(Eq)

///|
pub fn geometry_point_kind(value : String) -> GeometryPointKind? {
  match value {
    "free" => Some(FreePoint)
    "midpoint" => Some(MidpointPoint)
    _ => None
  }
}

///|
pub fn geometry_point_kind_name(value : GeometryPointKind) -> String {
  match value {
    FreePoint => "free"
    MidpointPoint => "midpoint"
  }
}

///|
pub impl ToJson for GeometryPointKind with fn to_json(self) {
  geometry_point_kind_name(self).to_json()
}

///|
pub impl @json.FromJson for GeometryPointKind with fn from_json(value, path) {
  match value {
    String(value) =>
      match geometry_point_kind(value) {
        Some(kind) => kind
        None =>
          raise @json.JsonDecodeError((path, "Unknown geometry point kind"))
      }
    _ => raise @json.JsonDecodeError((path, "Expected geometry point kind"))
  }
}

///|
pub fn default_geometry() -> GeometryDefinition {
  let free = fn(x, y, label) -> GeometryPoint {
    { kind: FreePoint, x, y, from: None, to: None, label, deleted: None, }
  }
  {
    version: 1,
    points: {
      "a": free(-2.0, -1.0, "A"),
      "b": free(2.0, -1.0, "B"),
      "c": free(0.0, 2.0, "C"),
      "m": {
        kind: MidpointPoint,
        x: 0.0,
        y: 0.0,
        from: Some("a"),
        to: Some("b"),
        label: "M",
        deleted: None,
      },
    },
    vectors: {
      "ab": { from: "a", to: "b", label: "AB", deleted: None, },
      "ac": { from: "a", to: "c", label: "AC", deleted: None, },
    },
    angles: {
      "bac": { from: "b", vertex: "a", to: "c", label: "θ", deleted: None, },
    },
  }
}

///|
pub fn has_geometry_data(scene : Scene) -> Bool {
  scene.objects.values().any(fn(object) { object.kind == Geometry }) ||
  scene.compositions
  .values()
  .any(fn(comp) {
    comp.states.values().any(fn(state) { state.geometry is Some(_) })
  })
}

///|
pub fn geometry_points(definition : GeometryDefinition) -> Map[String, Point] {
  let inputs : Array[@math_geometry.Input] = []
  for id, point in definition.points {
    if point.deleted == Some(true) {
      continue
    }
    let construction = match point.kind {
      FreePoint => @math_geometry.Free({ x: point.x, y: point.y, })
      MidpointPoint =>
        @math_geometry.Midpoint(
          point.from.unwrap_or(""),
          point.to.unwrap_or(""),
        )
    }
    inputs.push({ id, construction, })
  }
  let result : Map[String, Point] = Map([])
  for id, point in @math_geometry.evaluate(inputs).points {
    result[id] = { x: point.x, y: point.y, }
  }
  result
}

///|
pub fn geometry_validation_error(definition : GeometryDefinition) -> String? {
  if definition.version != 1 {
    return Some("対応していない幾何のバージョンです。")
  }
  if definition.points.length() > 128 ||
    definition.vectors.length() > 128 ||
    definition.angles.length() > 128 {
    return Some(
      "点・ベクトル・角度はそれぞれ128個までです。",
    )
  }
  for id, point in definition.points {
    if !geometry_id_valid(id) || point.label.length() > 100 {
      return Some("点のIDやラベルが長すぎます。")
    }
    if ![point.x, point.y].all(fn(v) {
        !v.is_nan() && !v.is_inf() && v.abs() <= 100000.0
      }) {
      return Some(
        "点の座標は有限の数値（±100000以内）にしてください。",
      )
    }
    if point.kind == FreePoint && (point.from is Some(_) || point.to is Some(_)) {
      return Some("自由な点には参照を指定できません。")
    }
  }
  let points = geometry_points(definition)
  for id, point in definition.points {
    if point.deleted != Some(true) && !points.contains(id) {
      return Some(
        "点の参照が欠けているか、循環しています：" +
        point.label,
      )
    }
  }
  for id, vector in definition.vectors {
    if !geometry_id_valid(id) || vector.label.length() > 100 {
      return Some("ベクトルのIDやラベルが長すぎます。")
    }
    if vector.deleted != Some(true) &&
      (!points.contains(vector.from) || !points.contains(vector.to)) {
      return Some(
        "ベクトルが参照する点がありません：" + vector.label,
      )
    }
  }
  for id, angle in definition.angles {
    if !geometry_id_valid(id) || angle.label.length() > 100 {
      return Some("角度のIDやラベルが長すぎます。")
    }
    if angle.deleted != Some(true) &&
      (
        !points.contains(angle.from) ||
        !points.contains(angle.vertex) ||
        !points.contains(angle.to)
      ) {
      return Some("角度が参照する点がありません：" + angle.label)
    }
  }
  None
}

///|
fn geometry_id_valid(id : String) -> Bool {
  !id.is_empty() &&
  id.length() <= 80 &&
  id
  .iter()
  .all(fn(c) {
    (c >= 'a' && c <= 'z') ||
    (c >= 'A' && c <= 'Z') ||
    (c >= '0' && c <= '9') ||
    c == '_' ||
    c == '-'
  }) &&
  !["__proto__", "constructor", "prototype"].contains(id)
}

///|
pub fn geometry_unit(state : ObjectState) -> Double {
  minimum(state.width.abs(), state.height.abs()) / 8.0
}

///|
pub fn geometry_texts(definition : GeometryDefinition) -> Array[String] {
  let texts = ["0123456789.-°（未定義）"]
  let ids = definition.points.keys().to_array()
  ids.sort()
  for id in ids {
    let value = definition.points[id]
    if value.deleted != Some(true) {
      texts.push(value.label)
    }
  }
  let ids = definition.vectors.keys().to_array()
  ids.sort()
  for id in ids {
    let value = definition.vectors[id]
    if value.deleted != Some(true) {
      texts.push(value.label)
    }
  }
  let ids = definition.angles.keys().to_array()
  ids.sort()
  for id in ids {
    let value = definition.angles[id]
    if value.deleted != Some(true) {
      texts.push(value.label)
    }
  }
  texts
}

///|
pub fn geometry_angle(from : Point, vertex : Point, to : Point) -> Double? {
  @math_geometry.angle(
    { x: from.x, y: from.y, },
    { x: vertex.x, y: vertex.y, },
    { x: to.x, y: to.y, },
  )
}

///|
pub fn point_distance(from : Point, to : Point) -> Double {
  @math_geometry.length(
    @math_geometry.vector({ x: from.x, y: from.y, }, { x: to.x, y: to.y, }),
  )
}

///|
pub fn interpolate_geometry(
  a : GeometryDefinition?,
  b : GeometryDefinition?,
  progress : Double,
  discrete : Double,
  interpolate : (Double, Double, Double) -> Double,
) -> GeometryDefinition? {
  guard a is Some(a) && b is Some(b) else {
    return if discrete < 0.5 { a } else { b }
  }
  let source = if discrete < 0.5 { a } else { b }
  let points = source.points.copy()
  for id, point in points {
    if point.kind == FreePoint &&
      a.points.get(id) is Some(first) &&
      b.points.get(id) is Some(last) &&
      first.kind == FreePoint &&
      last.kind == FreePoint &&
      first.deleted != Some(true) &&
      last.deleted != Some(true) {
      points[id] = {
        ..point,
        x: interpolate(first.x, last.x, progress),
        y: interpolate(first.y, last.y, progress),
      }
    }
  }
  Some({ ..source, points, })
}
