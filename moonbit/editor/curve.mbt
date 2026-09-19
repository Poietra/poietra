///|
pub(all) enum CurvePoint {
  First
  Second
} derive(Eq)

///|
pub(all) enum CurveCoordinate {
  X1
  Y1
  X2
  Y2
}

///|
pub fn curve_coordinate(value : Double) -> Double {
  (@scene.clamp(value, 0.0, 1.0) * 1000.0 + 0.5).floor() / 1000.0
}

///|
pub fn move_curve_point(
  value : @scene.Easing,
  point : CurvePoint,
  x : Double,
  y : Double,
) -> @scene.Easing {
  match value {
    CubicBezier(x1, y1, x2, y2) =>
      match point {
        First =>
          @scene.CubicBezier(curve_coordinate(x), curve_coordinate(y), x2, y2)
        Second =>
          @scene.CubicBezier(x1, y1, curve_coordinate(x), curve_coordinate(y))
      }
    _ => value
  }
}

///|
pub fn edit_curve_coordinate(
  value : @scene.Easing,
  coordinate : CurveCoordinate,
  next : Double,
) -> @scene.Easing {
  guard value is CubicBezier(x1, y1, x2, y2) else { return value }
  let next = curve_coordinate(next)
  match coordinate {
    X1 => @scene.CubicBezier(next, y1, x2, y2)
    Y1 => @scene.CubicBezier(x1, next, x2, y2)
    X2 => @scene.CubicBezier(x1, y1, next, y2)
    Y2 => @scene.CubicBezier(x1, y1, x2, next)
  }
}

///|
pub fn easing_curve_path(value : @scene.Easing) -> String {
  if value is CubicBezier(x1, y1, x2, y2) {
    return "M0 100 C\{x1 * 100.0} \{100.0 - y1 * 100.0} \{x2 * 100.0} \{100.0 - y2 * 100.0} 100 0"
  }
  let out = StringBuilder()
  for index = 0; index <= 40; index = index + 1 {
    let x = index.to_double() / 40.0
    let y = match value {
      Linear => x
      EaseIn => x * x * x
      EaseOut => {
        let u = 1.0 - x
        1.0 - u * u * u
      }
      EaseInOut =>
        if x < 0.5 {
          4.0 * x * x * x
        } else {
          let u = -2.0 * x + 2.0
          1.0 - u * u * u / 2.0
        }
      CubicBezier(_, _, _, _) => x
    }
    out.write_string(if index == 0 { "M" } else { " L" })
    out.write_string("\{x * 100.0} \{100.0 - y * 100.0}")
  }
  out.to_string()
}
