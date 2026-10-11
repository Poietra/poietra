///|
pub(all) struct Point {
  x : Double
  y : Double
} derive(Eq, Debug)

///|
pub(all) enum Construction {
  Free(Point)
  Midpoint(String, String)
} derive(Eq, Debug)

///|
pub(all) struct Input {
  id : String
  construction : Construction
} derive(Eq, Debug)

///|
pub(all) struct Evaluation {
  points : Map[String, Point]
  unresolved : Array[String]
} derive(Eq, Debug)

///|
/// Bounded, one-way constructions. Invalid/missing/cyclic dependencies are
/// omitted, never replaced by a guessed position or an unbounded solver.
pub fn evaluate(inputs : Array[Input]) -> Evaluation {
  let points : Map[String, Point] = Map([])
  if inputs.length() > 128 {
    return { points, unresolved: inputs.map(fn(input) { input.id }), }
  }
  for input in inputs {
    if input.construction is Free(p) &&
      !p.x.is_nan() &&
      !p.x.is_inf() &&
      !p.y.is_nan() &&
      !p.y.is_inf() {
      points[input.id] = p
    }
  }
  for _ in 0..<inputs.length() {
    let before = points.length()
    for input in inputs {
      if !points.contains(input.id) &&
        input.construction is Midpoint(a, b) &&
        points.get(a) is Some(a) &&
        points.get(b) is Some(b) {
        points[input.id] = {
          x: a.x / 2.0 + b.x / 2.0,
          y: a.y / 2.0 + b.y / 2.0,
        }
      }
    }
    if points.length() == before {
      break
    }
  }
  {
    points,
    unresolved: inputs
    .filter(fn(input) { !points.contains(input.id) })
    .map(fn(input) { input.id }),
  }
}

///|
pub fn vector(from : Point, to : Point) -> Point {
  { x: to.x - from.x, y: to.y - from.y, }
}

///|
pub fn length(vector : Point) -> Double {
  @math.hypot(vector.x, vector.y)
}

///|
/// Unsigned smaller angle, in degrees; a zero-length arm has no angle.
pub fn angle(from : Point, vertex : Point, to : Point) -> Double? {
  let a = vector(vertex, from)
  let b = vector(vertex, to)
  let la = length(a)
  let lb = length(b)
  if la <= 1.0e-12 || lb <= 1.0e-12 || la.is_inf() || lb.is_inf() {
    return None
  }
  let cosine = (a.x / la * (b.x / lb) + a.y / la * (b.y / lb))
    .max(-1.0)
    .min(1.0)
  let result = @math.acos(cosine) * 180.0 / @math.PI
  if result.is_nan() {
    None
  } else {
    Some(result)
  }
}
