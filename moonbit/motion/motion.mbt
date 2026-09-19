///|
/// Bound a progress value while preserving NaN, matching the original kernel.
fn bounded(value : Double) -> Double {
  if value < 0.0 {
    0.0
  } else if value > 1.0 {
    1.0
  } else {
    value
  }
}

///|
fn finite(value : Double) -> Bool {
  !value.is_nan() && !value.is_inf()
}

///|
pub fn ease(value : Double, kind : Int) -> Double {
  let t = if finite(value) { bounded(value) } else { 0.0 }
  match kind {
    1 =>
      if t < 0.5 {
        4.0 * t * t * t
      } else {
        let u = -2.0 * t + 2.0
        1.0 - u * u * u / 2.0
      }
    2 => t * t * t
    3 => {
      let u = 1.0 - t
      1.0 - u * u * u
    }
    _ => t
  }
}

///|
pub fn track_progress(
  time : Double,
  start : Double,
  duration : Double,
  easing : Int,
) -> Double {
  if time < start {
    return 0.0
  }
  if duration <= 0.0 {
    return 1.0
  }
  ease((time - start) / duration, easing)
}

///|
pub fn interpolate(from : Double, to : Double, progress : Double) -> Double {
  from + (to - from) * bounded(progress)
}

///|
pub fn cubic_bezier(
  p0 : Double,
  p1 : Double,
  p2 : Double,
  p3 : Double,
  progress : Double,
) -> Double {
  let t = bounded(progress)
  let u = 1.0 - t
  u * u * u * p0 + 3.0 * u * u * t * p1 + 3.0 * u * t * t * p2 + t * t * t * p3
}

///|
/// Invert the x curve before evaluating y, including flat endpoint tangents.
pub fn cubic_bezier_ease(
  value : Double,
  x1 : Double,
  y1 : Double,
  x2 : Double,
  y2 : Double,
) -> Double {
  let time = if finite(value) { bounded(value) } else { 0.0 }
  if time == 0.0 || time == 1.0 {
    return time
  }
  for v in [x1, y1, x2, y2] {
    if !finite(v) || v < 0.0 || v > 1.0 {
      return time
    }
  }
  let mut low = 0.0
  let mut high = 1.0
  for _ in 0..<48 {
    let parameter = (low + high) * 0.5
    let x = cubic_bezier(0.0, x1, x2, 1.0, parameter)
    if x == time {
      return cubic_bezier(0.0, y1, y2, 1.0, parameter)
    }
    if x < time {
      low = parameter
    } else {
      high = parameter
    }
  }
  bounded(cubic_bezier(0.0, y1, y2, 1.0, (low + high) * 0.5))
}
