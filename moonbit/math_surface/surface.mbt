///|
pub(all) struct Point3 {
  x : Double
  y : Double
  z : Double
} derive(Eq, Debug)

///|
pub(all) struct Projected {
  x : Double
  y : Double
  depth : Double
} derive(Eq, Debug)

///|
pub(all) struct Triangle {
  a : Point3
  b : Point3
  c : Point3
} derive(Eq)

///|
pub(all) struct Mesh {
  triangles : Array[Triangle]
  omitted : Int
  evaluations : Int
}

///|
pub struct Program {
  priv x : @math_plot.Program
  priv y : @math_plot.Program
  priv z : @math_plot.Program
}

///|
pub fn prepare(
  x : String,
  y : String,
  z : String,
  heightfield : Bool,
) -> Program raise @math_plot.InvalidExpression {
  {
    x: @math_plot.prepare_surface(if heightfield { "x" } else { x }),
    y: @math_plot.prepare_surface(if heightfield { "y" } else { y }),
    z: @math_plot.prepare_surface(z),
  }
}

///|
pub fn Program::point(
  self : Program,
  u : Double,
  v : Double,
  a : Double,
  b : Double,
  c : Double,
) -> Point3? {
  if self.x.evaluate_at(u, v, a, b, c) is Some(x) &&
    self.y.evaluate_at(u, v, a, b, c) is Some(y) &&
    self.z.evaluate_at(u, v, a, b, c) is Some(z) &&
    x.abs() <= 100000.0 &&
    y.abs() <= 100000.0 &&
    z.abs() <= 100000.0 {
    Some({ x, y, z, })
  } else {
    None
  }
}

///|
pub fn project(point : Point3, yaw : Double, pitch : Double) -> Projected {
  let yaw = yaw * @math.PI / 180.0
  let pitch = pitch * @math.PI / 180.0
  let x = point.x * @math.cos(yaw) - point.y * @math.sin(yaw)
  let y = point.x * @math.sin(yaw) + point.y * @math.cos(yaw)
  {
    x,
    y: -(y * @math.sin(pitch) + point.z * @math.cos(pitch)),
    depth: -y * @math.cos(pitch) + point.z * @math.sin(pitch),
  }
}

///|
fn distance(a : Point3, b : Point3) -> Double {
  @math.hypot(@math.hypot(a.x - b.x, a.y - b.y), a.z - b.z)
}

///|
/// Bounded grid triangulation. Midpoint probes reject unresolved/pole-spanning
/// cells; this is a visualization approximation, not certified topology.
pub fn sample(
  program : Program,
  u_min : Double,
  u_max : Double,
  v_min : Double,
  v_max : Double,
  a : Double,
  b : Double,
  c : Double,
  steps : Int,
) -> Mesh {
  guard steps >= 4 && steps <= 48 && u_max > u_min && v_max > v_min else {
    return { triangles: [], omitted: 0, evaluations: 0, }
  }
  let points = Array::makei((steps + 1) * (steps + 1), fn(i) {
    program.point(
      u_min +
      (u_max - u_min) * (i % (steps + 1)).to_double() / steps.to_double(),
      v_min +
      (v_max - v_min) * (i / (steps + 1)).to_double() / steps.to_double(),
      a,
      b,
      c,
    )
  })
  let triangles : Array[Triangle] = []
  let mut omitted = 0
  for y in 0..<steps {
    for x in 0..<steps {
      let at = y * (steps + 1) + x
      let middle = program.point(
        u_min + (u_max - u_min) * (x.to_double() + 0.5) / steps.to_double(),
        v_min + (v_max - v_min) * (y.to_double() + 0.5) / steps.to_double(),
        a,
        b,
        c,
      )
      if points[at] is Some(p) &&
        points[at + 1] is Some(q) &&
        points[at + steps + 1] is Some(r) &&
        points[at + steps + 2] is Some(s) &&
        middle is Some(m) {
        let predicted : Point3 = {
          x: (p.x + q.x + r.x + s.x) / 4.0,
          y: (p.y + q.y + r.y + s.y) / 4.0,
          z: (p.z + q.z + r.z + s.z) / 4.0,
        }
        let span = distance(p, q)
          .max(distance(p, r))
          .max(distance(q, s))
          .max(distance(r, s))
          .max(0.01)
        if distance(predicted, m) <= span * 0.8 &&
          span <= (u_max - u_min).max(v_max - v_min).max(1.0) * 8.0 {
          triangles.push({ a: p, b: q, c: s, })
          triangles.push({ a: p, b: s, c: r, })
        } else {
          omitted += 1
        }
      } else {
        omitted += 1
      }
    }
  }
  {
    triangles,
    omitted,
    evaluations: ((steps + 1) * (steps + 1) + steps * steps) * 3,
  }
}
