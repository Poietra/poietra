///|
pub(all) enum OutlineSource {
  Empty
  Ellipse(Double, Double, String)
  Measured(String)
  Shaft(String, Double)
}

///|
/// The same quantized coordinates feed SVG and native Canvas paths.
pub fn outline_source(shape : Shape) -> OutlineSource {
  match shape {
    Ellipse(rx, ry) => {
      let x = number(rx)
      let y = number(ry)
      if x == "0" || y == "0" {
        Empty
      } else {
        Ellipse(
          rx,
          ry,
          "M\{x} 0 A\{x} \{y} 0 1 1 \{number(-rx)} 0 A\{x} \{y} 0 1 1 \{x} 0 Z",
        )
      }
    }
    Rectangle(width, height, r) => {
      if number(width) == "0" || number(height) == "0" {
        return Empty
      }
      let x = width / 2.0
      let y = height / 2.0
      if r == 0.0 {
        return Measured(
          "M\{number(-x)} \{number(-y)} H\{number(x)} V\{number(y)} H\{number(-x)} Z",
        )
      }
      Measured(
        "M\{number(-x + r)} \{number(-y)} H\{number(x - r)} A\{number(r)} \{number(r)} 0 0 1 \{number(x)} \{number(-y + r)} V\{number(y - r)} A\{number(r)} \{number(r)} 0 0 1 \{number(x - r)} \{number(y)} H\{number(-x + r)} A\{number(r)} \{number(r)} 0 0 1 \{number(-x)} \{number(y - r)} V\{number(-y + r)} A\{number(r)} \{number(r)} 0 0 1 \{number(-x + r)} \{number(-y)} Z",
      )
    }
    Path(path) => Measured(path)
    Arrow(geometry) | NumberLine(geometry) =>
      Shaft("M0 0 H\{number(geometry.length)}", geometry.length)
  }
}
