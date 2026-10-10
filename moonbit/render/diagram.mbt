///|
pub(all) struct DiagramCurve {
  id : String
  path : String
} derive(Eq)

///|
pub(all) struct DiagramGeometry {
  curves : Array[DiagramCurve]
  labels : Array[GraphLabel]
  limited : Bool
} derive(Eq)

///|
fn diagram_paths(state : @scene.ObjectState) -> Array[(String, String)] {
  let definition = state.geometry.unwrap_or(@scene.default_geometry())
  let points = @scene.geometry_points(definition)
  let scale = @scene.geometry_unit(state)
  let at = fn(p : @scene.Point) -> @scene.Point {
    { x: p.x * scale, y: -p.y * scale, }
  }
  let paths : Array[(String, String)] = []
  let ids = definition.vectors.keys().to_array()
  ids.sort()
  for id in ids {
    let v = definition.vectors[id]
    if v.deleted == Some(true) {
      continue
    }
    if points.get(v.from) is Some(a) && points.get(v.to) is Some(b) {
      let a = at(a)
      let b = at(b)
      let length = @math.hypot(b.x - a.x, b.y - a.y)
      if length <= 1.0e-9 {
        continue
      }
      let ux = (b.x - a.x) / length
      let uy = (b.y - a.y) / length
      let head = length.min(10.0)
      paths.push(
        (
          "vectors/" + id,
          "M\{number(a.x)} \{number(a.y)} L\{number(b.x)} \{number(b.y)} M\{number(b.x - ux * head - uy * head * 0.4)} \{number(b.y - uy * head + ux * head * 0.4)} L\{number(b.x)} \{number(b.y)} L\{number(b.x - ux * head + uy * head * 0.4)} \{number(b.y - uy * head - ux * head * 0.4)}",
        ),
      )
    }
  }
  let ids = definition.angles.keys().to_array()
  ids.sort()
  for id in ids {
    let value = definition.angles[id]
    if value.deleted == Some(true) {
      continue
    }
    if points.get(value.from) is Some(a) &&
      points.get(value.vertex) is Some(v) &&
      points.get(value.to) is Some(b) {
      let a = at(a)
      let v = at(v)
      let b = at(b)
      let length = @math.hypot(a.x - v.x, a.y - v.y).min(
        @math.hypot(b.x - v.x, b.y - v.y),
      )
      if length <= 1.0e-9 {
        continue
      }
      let start = @math.atan2(a.y - v.y, a.x - v.x)
      let mut delta = @math.atan2(b.y - v.y, b.x - v.x) - start
      if delta > @math.PI {
        delta -= 2.0 * @math.PI
      }
      if delta < -@math.PI {
        delta += 2.0 * @math.PI
      }
      let radius = length.min(28.0) * 0.75
      let path = StringBuilder()
      for i in 0..<25 {
        let angle = start + delta * i.to_double() / 24.0
        path.write_string(
          (if i == 0 { "M" } else { "L" }) +
          "\{number(v.x + @math.cos(angle) * radius)} \{number(v.y + @math.sin(angle) * radius)}",
        )
      }
      paths.push(("angles/" + id, path.to_string()))
    }
  }
  let ids = definition.points.keys().to_array()
  ids.sort()
  for id in ids {
    if points.get(id) is Some(p) {
      let p = at(p)
      let r = if definition.points[id].kind == @scene.MidpointPoint {
        3.0
      } else {
        4.0
      }
      paths.push(
        (
          "points/" + id,
          "M\{number(p.x + r)} \{number(p.y)} A\{number(r)} \{number(r)} 0 1 1 \{number(p.x - r)} \{number(p.y)} A\{number(r)} \{number(r)} 0 1 1 \{number(p.x + r)} \{number(p.y)} Z",
        ),
      )
    }
  }
  paths
}

///|
pub fn diagram_geometry(
  state : @scene.ObjectState,
  progress : Double,
) -> DiagramGeometry {
  if unit(progress) == 0.0 {
    return { curves: [], labels: [], limited: false, }
  }
  let definition = state.geometry.unwrap_or(@scene.default_geometry())
  let points = @scene.geometry_points(definition)
  let scale = @scene.geometry_unit(state)
  let paths = diagram_paths(state)
  let labels : Array[GraphLabel] = []
  let ids = definition.points.keys().to_array()
  ids.sort()
  for id in ids {
    if points.get(id) is Some(p) {
      labels.push({
        x: p.x * scale + 8.0,
        y: -p.y * scale - 8.0,
        text: definition.points[id].label,
      })
    }
  }
  for _, v in definition.vectors {
    if v.deleted != Some(true) &&
      points.get(v.from) is Some(a) &&
      points.get(v.to) is Some(b) {
      labels.push({
        x: (a.x / 2.0 + b.x / 2.0) * scale + 8.0,
        y: -(a.y / 2.0 + b.y / 2.0) * scale + 16.0,
        text: v.label,
      })
    }
  }
  for _, angle in definition.angles {
    if angle.deleted != Some(true) &&
      points.get(angle.from) is Some(a) &&
      points.get(angle.vertex) is Some(v) &&
      points.get(angle.to) is Some(b) {
      let text = match @scene.geometry_angle(a, v, b) {
        Some(degrees) =>
          angle.label + " " + number((degrees * 10.0).round() / 10.0) + "°"
        None => angle.label + "（未定義）"
      }
      labels.push({ x: v.x * scale + 26.0, y: -v.y * scale - 26.0, text, })
    }
  }
  {
    curves: paths.map(fn(pair) { { id: pair.0, path: pair.1, } }),
    labels,
    limited: @scene.geometry_validation_error(definition) is Some(_),
  }
}

///|
fn diagram_markup(
  geometry : DiagramGeometry,
  state : @scene.ObjectState,
  progress : Double,
) -> String {
  let body = StringBuilder()
  let reveal = if progress < 1.0 {
    " pathLength=\"1\" stroke-dasharray=\"1\" stroke-dashoffset=\"\{number(1.0 - progress)}\""
  } else {
    ""
  }
  for curve in geometry.curves {
    body.write_string(
      "<path data-geometry-element=\"\{escape_xml(curve.id)}\" d=\"\{curve.path}\" fill=\"none\"\{reveal}/>",
    )
  }
  body.write_string(
    "<g fill=\"\{color(state.fill)}\" stroke=\"none\" font-family=\"Poietra Inter, Poietra Noto Sans JP, sans-serif\" font-size=\"12\" opacity=\"\{number(progress * 0.75)}\">",
  )
  for label in geometry.labels {
    body.write_string(
      "<text x=\"\{number(label.x)}\" y=\"\{number(label.y)}\">\{escape_xml(label.text)}</text>",
    )
  }
  body.write_string("</g>")
  body.to_string()
}
