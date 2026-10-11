///|
pub(all) struct Segment {
  x0 : Double
  y0 : Double
  x1 : Double
  y1 : Double
} derive(Eq, Debug)

///|
pub(all) struct Plot {
  segments : Array[Segment]
  /// Unclipped chords in viewport coordinates. Consecutive chords share
  /// endpoints across viewport edges; only breaks, undefined values and
  /// unresolved jumps separate them, so a region can be closed before clipping.
  chords : Array[Segment]
  limited : Bool
  evaluations : Int
} derive(Eq, Debug)

///|
/// Mathematical coordinates are distinct from a centered, y-down drawing viewport.
pub(all) struct Viewport {
  x_min : Double
  x_max : Double
  y_min : Double
  y_max : Double
  width : Double
  height : Double
}

///|
pub fn Viewport::point(
  self : Viewport,
  x : Double,
  y : Double,
) -> (Double, Double) {
  (
    ((x - self.x_min) / (self.x_max - self.x_min) - 0.5) * self.width,
    (0.5 - (y - self.y_min) / (self.y_max - self.y_min)) * self.height,
  )
}

///|
priv struct Sampler {
  program : Program
  viewport : Viewport
  a : Double
  b : Double
  c : Double
  segments : Array[Segment]
  chords : Array[Segment]
  mut evaluations : Int
  mut limited : Bool
}

///|
fn Sampler::point(self : Sampler, x : Double) -> (Double, Double)? {
  if self.evaluations >= 16384 {
    self.limited = true
    return None
  }
  self.evaluations += 1
  guard self.program.evaluate(x, self.a, self.b, self.c) is Some(y) else {
    return None
  }
  let point = self.viewport.point(x, y)
  if point.1.is_nan() || point.1.is_inf() || point.1.abs() > 1.0e12 {
    None
  } else {
    Some(point)
  }
}

///|
/// Clip before generating paths, so non-finite/offscreen coordinates never reach a host.
fn Sampler::line(
  self : Sampler,
  a : (Double, Double),
  b : (Double, Double),
) -> Unit {
  if self.chords.length() >= 4096 {
    self.limited = true
    return
  }
  self.chords.push({ x0: a.0, y0: a.1, x1: b.0, y1: b.1, })
  let dx = b.0 - a.0
  let dy = b.1 - a.1
  let mut low = 0.0
  let mut high = 1.0
  for
    (p, q) in [
      (-dx, a.0 + self.viewport.width / 2.0),
      (dx, self.viewport.width / 2.0 - a.0),
      (-dy, a.1 + self.viewport.height / 2.0),
      (dy, self.viewport.height / 2.0 - a.1),
    ] {
    if p == 0.0 {
      if q < 0.0 {
        return
      }
    } else if p < 0.0 {
      low = low.max(q / p)
    } else {
      high = high.min(q / p)
    }
  }
  if low > high {
    return
  }
  self.segments.push({
    x0: a.0 + low * dx,
    y0: a.1 + low * dy,
    x1: a.0 + high * dx,
    y1: a.1 + high * dy,
  })
}

///|
fn Sampler::interval(
  self : Sampler,
  low : Double,
  high : Double,
  a : (Double, Double)?,
  b : (Double, Double)?,
  depth : Int,
) -> Unit {
  if self.evaluations >= 16384 || self.segments.length() >= 4096 {
    self.limited = true
    return
  }
  let middle = (low + high) / 2.0
  let m = self.point(middle)
  let mut smooth = false
  if a is Some(a) && b is Some(b) && m is Some(m) {
    // Test in the actual drawing coordinates. Quarter probes avoid a midpoint
    // accidentally landing on the chord of an inflection or oscillation.
    let q0 = self.point((low + middle) / 2.0)
    let q1 = self.point((middle + high) / 2.0)
    if q0 is Some(q0) && q1 is Some(q1) {
      smooth = (m.1 - (a.1 + b.1) / 2.0).abs() <= 0.5 &&
        (q0.1 - (a.1 * 0.75 + b.1 * 0.25)).abs() <= 0.5 &&
        (q1.1 - (a.1 * 0.25 + b.1 * 0.75)).abs() <= 0.5
    }
    if smooth {
      self.line(a, b)
      return
    }
  }
  if depth >= 10 {
    // Never join an unresolved jump across a pole. Omit it, rather than invent
    // a vertical connecting stroke. Limits are reported with the derived plot.
    if a is Some(_) && b is Some(_) && m is Some(_) {
      self.limited = true
    }
    return
  }
  // Wholly undefined regions need only a few levels of probing. No claim is
  // made that finite sampling discovers every feature of an arbitrary function.
  if a is None && b is None && m is None && depth >= 3 {
    return
  }
  self.interval(low, middle, a, m, depth + 1)
  self.interval(middle, high, m, b, depth + 1)
}

///|
pub fn plot(
  program : Program,
  viewport : Viewport,
  a : Double,
  b : Double,
  c : Double,
  breaks : Array[Double],
) -> Plot {
  let sampler : Sampler = {
    program,
    viewport,
    a,
    b,
    c,
    segments: [],
    chords: [],
    evaluations: 0,
    limited: false,
  }
  for
    value in [
      viewport.x_min,
      viewport.x_max,
      viewport.y_min,
      viewport.y_max,
      viewport.width,
      viewport.height,
      a,
      b,
      c,
    ] {
    if value.is_nan() || value.is_inf() {
      return { segments: [], chords: [], limited: false, evaluations: 0, }
    }
  }
  if breaks.length() > 32 {
    return { segments: [], chords: [], limited: true, evaluations: 0, }
  }
  if viewport.x_max <= viewport.x_min ||
    viewport.y_max <= viewport.y_min ||
    viewport.width <= 0.0 ||
    viewport.height <= 0.0 {
    return { segments: [], chords: [], limited: false, evaluations: 0, }
  }
  let boundaries = [viewport.x_min]
  for value in breaks {
    if value > viewport.x_min && value < viewport.x_max {
      boundaries.push(value)
    }
  }
  boundaries.push(viewport.x_max)
  boundaries.sort()
  for index = 0; index + 1 < boundaries.length(); index = index + 1 {
    let start = boundaries[index]
    let end = boundaries[index + 1]
    if start == end {
      continue
    }
    let margin = ((end - start) * 1.0e-9).max(1.0e-12)
    let start = if index == 0 { start } else { start + margin }
    let end = if index + 2 == boundaries.length() { end } else { end - margin }
    if end <= start {
      continue
    }
    let mut low = start
    let mut a = sampler.point(low)
    for i = 1; i <= 64; i = i + 1 {
      let high = start + (end - start) * i.to_double() / 64.0
      let b = sampler.point(high)
      sampler.interval(low, high, a, b, 0)
      low = high
      a = b
      if sampler.evaluations >= 16384 || sampler.chords.length() >= 4096 {
        break
      }
    }
  }
  {
    segments: sampler.segments,
    chords: sampler.chords,
    limited: sampler.limited,
    evaluations: sampler.evaluations,
  }
}
