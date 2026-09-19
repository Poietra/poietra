///|
pub let colors : Array[String] = [
  "#d7d8e4", "#67c4d9", "#f4ce55", "#b5d396", "#ef8078", "#d5a3bd", "#8a8fe9", "#ffffff",
]

///|
pub let object_kinds : Array[ObjectKind] = [
  Circle,
  Rectangle,
  Text,
  Equation,
  Path,
  Arrow,
  NumberLine,
  Image,
  Video,
]

///|
pub fn object_kind_label(kind : ObjectKind) -> String {
  match kind {
    Circle => "Circle"
    Rectangle => "Rectangle"
    Text => "Text"
    Equation => "Equation"
    Path => "Path"
    Arrow => "Arrow"
    NumberLine => "Number line"
    Image => "Image"
    Video => "Video"
  }
}

///|
pub let animations : Array[AnimationKind] = [Move, Write, Fade, Grow, Cut]

///|
pub fn animation_label(kind : AnimationKind) -> String {
  match kind {
    Move => "Move"
    Write => "Write"
    Fade => "Fade"
    Grow => "Grow"
    Cut => "Cut"
  }
}
