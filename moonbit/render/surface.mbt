///|
priv struct PreparedSurface {
  definition : @scene.SurfaceDefinition
  width : Double
  height : Double
  fill : String
  geometry : DiagramGeometry
}

///|
let surface_programs : Map[String, @math_surface.Program?] = Map([])

///|
let prepared_surfaces : Map[String, PreparedSurface] = Map([])

///|
let surface_sources : Array[String] = []

///|
fn surface_shade(source : String, brightness : Double) -> String {
  let value = color(source)
  if value.length() != 7 || !value.has_prefix("#") {
    return value
  }
  let channels = [1, 3, 5].map(fn(i) {
    let channel = @string.parse_int(value[i:i + 2], base=16) catch { _ => 0 }
    (channel.to_double() * brightness).round().to_int().to_string()
  })
  "rgb(" + channels.join(",") + ")"
}

///|
fn clip_surface_polygon(
  points : Array[@math_surface.Projected],
  width : Double,
  height : Double,
) -> Array[@math_surface.Projected] {
  let mut points = points
  for side in 0..<4 {
    let bound = if side < 2 { width / 2.0 } else { height / 2.0 }
    let coordinate = fn(p : @math_surface.Projected) {
      if side < 2 {
        p.x
      } else {
        p.y
      }
    }
    let sign = if side % 2 == 0 { 1.0 } else { -1.0 }
    let inside = fn(p) { coordinate(p) * sign <= bound }
    let clipped : Array[@math_surface.Projected] = []
    if points.is_empty() {
      break
    }
    for i in 0..<points.length() {
      let p = points[i]
      let q = points[(i + 1) % points.length()]
      if inside(p) {
        clipped.push(p)
      }
      if inside(p) != inside(q) {
        let t = (bound * sign - coordinate(p)) / (coordinate(q) - coordinate(p))
        clipped.push({
          x: p.x + (q.x - p.x) * t,
          y: p.y + (q.y - p.y) * t,
          depth: p.depth + (q.depth - p.depth) * t,
        })
      }
    }
    points = clipped
  }
  points
}

///|
fn prepare_surface_geometry(
  state : @scene.ObjectState,
  definition : @scene.SurfaceDefinition,
  program : @math_surface.Program,
) -> DiagramGeometry {
  let mesh = @math_surface.sample(
    program,
    definition.uMin,
    definition.uMax,
    definition.vMin,
    definition.vMax,
    definition.a,
    definition.b,
    definition.c,
    definition.steps,
  )
  let scale = @scene.geometry_unit(state) * definition.zoom
  let width = state.width.abs()
  let height = state.height.abs()
  let project = fn(p) {
    let p = @math_surface.project(p, definition.yaw, definition.pitch)
    @math_surface.Projected::{ ..p, x: p.x * scale, y: p.y * scale, }
  }
  let faces : Array[(Double, Int, DiagramCurve)] = []
  for index, triangle in mesh.triangles {
    let a = project(triangle.a)
    let b = project(triangle.b)
    let c = project(triangle.c)
    let points = clip_surface_polygon([a, b, c], width, height)
    if points.length() < 3 {
      continue
    }
    let path = StringBuilder()
    for i, p in points {
      path.write_string(
        (if i == 0 { "M" } else { "L" }) + number(p.x) + " " + number(p.y),
      )
    }
    path.write_string("Z")
    let u = @math_surface.Point3::{
      x: triangle.b.x - triangle.a.x,
      y: triangle.b.y - triangle.a.y,
      z: triangle.b.z - triangle.a.z,
    }
    let v = @math_surface.Point3::{
      x: triangle.c.x - triangle.a.x,
      y: triangle.c.y - triangle.a.y,
      z: triangle.c.z - triangle.a.z,
    }
    let normal = @math_surface.project(
      {
        x: u.y * v.z - u.z * v.y,
        y: u.z * v.x - u.x * v.z,
        z: u.x * v.y - u.y * v.x,
      },
      definition.yaw,
      definition.pitch,
    )
    let norm = @math.hypot(@math.hypot(normal.x, normal.y), normal.depth)
    let brightness = if norm < 1.0e-12 {
      0.6
    } else {
      0.35 +
      0.65 *
      (normal.x * 0.3 + normal.y * 0.4 + normal.depth * 0.85).abs() /
      norm
    }
    faces.push(
      (
        (a.depth + b.depth + c.depth) / 3.0,
        index,
        {
          id: "faces/\{index}",
          path: path.to_string(),
          fill: Some(
            if definition.filled {
              surface_shade(state.fill, brightness.min(1.0))
            } else {
              "none"
            },
          ),
          stroke: if definition.wireframe {
            None
          } else {
            Some("none")
          },
        },
      ),
    )
  }
  faces.sort_by(fn(a, b) {
    if a.0 < b.0 {
      -1
    } else if a.0 > b.0 {
      1
    } else {
      a.1.compare(b.1)
    }
  })
  let curves = faces.map(fn(face) { face.2 })
  let labels : Array[GraphLabel] = []
  if definition.axes {
    for
      index, p in [
        @math_surface.Point3::{ x: 3.0, y: 0.0, z: 0.0, },
        { x: 0.0, y: 3.0, z: 0.0, },
        { x: 0.0, y: 0.0, z: 3.0, },
      ] {
      let p = project(p)
      let factor = (width / 2.0 / p.x.abs().max(1.0e-9))
        .min(height / 2.0 / p.y.abs().max(1.0e-9))
        .min(1.0) *
        0.9
      curves.push({
        id: "axes/\{index}",
        path: "M0 0 L\{number(p.x*factor)} \{number(p.y*factor)}",
        fill: None,
        stroke: None,
      })
      labels.push({
        x: p.x * factor,
        y: p.y * factor,
        text: ["x", "y", "z"][index],
      })
    }
  }
  { curves, labels, limited: mesh.omitted > 0, }
}

///|
pub fn surface_geometry(
  state : @scene.ObjectState,
  progress : Double,
) -> DiagramGeometry {
  if unit(progress) == 0.0 {
    return { curves: [], labels: [], limited: false, }
  }
  let definition = state.surface.unwrap_or(@scene.default_surface())
  let key = @scene.surface_kind_name(definition.kind) +
    "|" +
    definition.xExpression +
    "|" +
    definition.yExpression +
    "|" +
    definition.zExpression
  if prepared_surfaces.get(key) is Some(previous) &&
    previous.definition == definition &&
    previous.width == state.width &&
    previous.height == state.height &&
    previous.fill == state.fill {
    return previous.geometry
  }
  let program = match surface_programs.get(key) {
    Some(program) => program
    None => {
      if surface_sources.length() >= 16 {
        let old = surface_sources.remove(0)
        surface_programs.remove(old)
        prepared_surfaces.remove(old)
      }
      let program = Some(
        @math_surface.prepare(
          definition.xExpression,
          definition.yExpression,
          definition.zExpression,
          definition.kind == @scene.Heightfield,
        ),
      ) catch {
        _ => None
      }
      surface_sources.push(key)
      surface_programs[key] = program
      program
    }
  }
  guard program is Some(program) else {
    return { curves: [], labels: [], limited: true, }
  }
  let geometry = prepare_surface_geometry(state, definition, program)
  prepared_surfaces[key] = {
    definition,
    width: state.width,
    height: state.height,
    fill: state.fill,
    geometry,
  }
  geometry
}
