///|
pub(all) enum Shape {
  Ellipse(Double, Double)
  Rectangle(Double, Double, Double)
  Path(String)
  Arrow(ArrowGeometry)
  NumberLine(ArrowGeometry)
} derive(Eq)

///|
pub(all) struct ArrowGeometry {
  length : Double
  angle : Double
  head : Double
  spread : Double
} derive(Eq)

///|
pub fn shape_geometry(
  kind : @scene.ObjectKind,
  state : @scene.ObjectState,
) -> Shape? {
  let width = finite(state.width)
  let height = finite(state.height)
  match kind {
    Circle => Some(Ellipse(width.abs() / 2.0, height.abs() / 2.0))
    Rectangle =>
      Some(
        Rectangle(
          width.abs(),
          height.abs(),
          finite(state.cornerRadius)
          .min(width.abs() / 2.0)
          .min(height.abs() / 2.0)
          .max(0.0),
        ),
      )
    Path =>
      Some(
        Path(
          "M0 0 C\{number(state.path.c1.x)} \{number(state.path.c1.y)} \{number(state.path.c2.x)} \{number(state.path.c2.y)} \{number(width)} \{number(height)}",
        ),
      )
    Arrow | NumberLine => {
      let length = @math.hypot(width, height)
      let head = length.min(
        (finite(state.strokeWidth).max(0.0) * 3.0).max(10.0),
      )
      let geometry : ArrowGeometry = {
        length,
        angle: @math.atan2(height, width) * 180.0 / @math.PI,
        head,
        spread: head * 0.45,
      }
      Some(
        if kind == @scene.Arrow {
          Arrow(geometry)
        } else {
          NumberLine(geometry)
        },
      )
    }
    _ => None
  }
}

///|
pub fn arrow_head_progress(progress : Double) -> Double {
  unit((progress - 0.8) / (1.0 - 0.8))
}

///|
pub fn numberline_tick_progress(progress : Double, index : Int) -> Double {
  unit(progress * 11.0 - index.to_double())
}

///|
pub fn arrow_head_path(shape : ArrowGeometry) -> String {
  "M\{number(shape.length - shape.head)} \{number(-shape.spread)} L\{number(shape.length)} 0 L\{number(shape.length - shape.head)} \{number(shape.spread)}"
}

///|
pub fn numberline_tick_path(length : Double, index : Int) -> String {
  "M\{number(length * index.to_double() / 10.0)} -6 V6"
}

///|
fn cubic(p1 : Double, p2 : Double, p3 : Double, t : Double) -> Double {
  let u = 1.0 - t
  u * u * u * 0.0 + 3.0 * u * u * t * p1 + 3.0 * u * t * t * p2 + t * t * t * p3
}

///|
pub fn cubic_range(p1 : Double, p2 : Double, p3 : Double) -> (Double, Double) {
  let a = 3.0 * p1 - 3.0 * p2 + p3
  let b = 2.0 * (p2 - 2.0 * p1)
  let c = p1
  let roots = []
  if a.abs() < 1.0e-12 {
    if b.abs() > 1.0e-12 {
      roots.push(-c / b)
    }
  } else {
    let discriminant = b * b - 4.0 * a * c
    if discriminant >= 0.0 {
      roots.push((-b + discriminant.sqrt()) / (2.0 * a))
      roots.push((-b - discriminant.sqrt()) / (2.0 * a))
    }
  }
  let mut low = @scene.minimum(0.0, p3)
  let mut high = @scene.maximum(0.0, p3)
  for t in roots {
    if t > 0.0 && t < 1.0 {
      let value = cubic(p1, p2, p3, t)
      low = @scene.minimum(low, value)
      high = @scene.maximum(high, value)
    }
  }
  (low, high)
}

///|
pub fn object_bounds(item : Drawable, resources : Resources) -> Bounds {
  let s = item.state
  let x = finite(s.x)
  let y = finite(s.y)
  let width = finite(s.width)
  let height = finite(s.height)
  let equation = if item.kind == @scene.Equation {
    (resources.equation)(s.text)
  } else {
    None
  }
  let write_stroke = if equation is Some(_) &&
    item.progress > 0.0 &&
    item.progress < 1.0 {
    18.0 * finite(s.fontSize).max(0.0) / 1000.0
  } else {
    0.0
  }
  let stroke = finite(s.strokeWidth).max(0.0).max(write_stroke) / 2.0
  let bounds : Bounds = match item.kind {
    Path => {
      let (left, right) = cubic_range(
        finite(s.path.c1.x),
        finite(s.path.c2.x),
        width,
      )
      let (top, bottom) = cubic_range(
        finite(s.path.c1.y),
        finite(s.path.c2.y),
        height,
      )
      { x: x + left, y: y + top, width: right - left, height: bottom - top, }
    }
    Arrow | NumberLine => {
      let angle = @math.atan2(height, width)
      let length = @math.hypot(width, height)
      let head = length.min((stroke * 2.0 * 3.0).max(10.0))
      let spread = if item.kind == @scene.NumberLine {
        (head * 0.45).max(6.0)
      } else {
        head * 0.45
      }
      let sine = @math.sin(angle)
      let cosine = @math.cos(angle)
      let points = [
        (0.0, 0.0),
        (width, height),
        (
          width - head * cosine + spread * sine,
          height - head * sine - spread * cosine,
        ),
        (
          width - head * cosine - spread * sine,
          height - head * sine + spread * cosine,
        ),
      ]
      if item.kind == @scene.NumberLine {
        for t in [0.0, 1.0] {
          points.push((width * t + 6.0 * sine, height * t - 6.0 * cosine))
          points.push((width * t - 6.0 * sine, height * t + 6.0 * cosine))
        }
      }
      let mut left = 0.0
      let mut right = 0.0
      let mut top = 0.0
      let mut bottom = 0.0
      for (px, py) in points {
        left = @scene.minimum(left, px)
        right = @scene.maximum(right, px)
        top = @scene.minimum(top, py)
        bottom = @scene.maximum(bottom, py)
      }
      { x: x + left, y: y + top, width: right - left, height: bottom - top, }
    }
    _ => {
      let (width, height) = if item.kind == @scene.Text ||
        item.kind == @scene.Equation {
        let size = finite(s.fontSize).max(0.0)
        match equation {
          Some(equation) =>
            (equation.width * size / 1000.0, equation.height * size / 1000.0)
          None => {
            let metrics = (resources.measure_text)(s.text, size)
            (metrics.width, metrics.height)
          }
        }
      } else {
        (width.abs(), height.abs())
      }
      { x: x - width / 2.0, y: y - height / 2.0, width, height, }
    }
  }
  {
    x: bounds.x - stroke,
    y: bounds.y - stroke,
    width: bounds.width + stroke * 2.0,
    height: bounds.height + stroke * 2.0,
  }
}
