///|
pub(all) enum StageTool {
  SelectTool
  DrawTool(@scene.ObjectKind)
} derive(Eq)

///|
pub(all) enum StageTransform {
  RotateObject
  ResizeNW
  ResizeNE
  ResizeSE
  ResizeSW
} derive(Eq)

///|
pub fn stage_transform(value : String) -> StageTransform? {
  match value {
    "rotate" => Some(RotateObject)
    "nw" => Some(ResizeNW)
    "ne" => Some(ResizeNE)
    "se" => Some(ResizeSE)
    "sw" => Some(ResizeSW)
    _ => None
  }
}

///|
pub fn stage_transform_name(value : StageTransform) -> String {
  match value {
    RotateObject => "rotate"
    ResizeNW => "nw"
    ResizeNE => "ne"
    ResizeSE => "se"
    ResizeSW => "sw"
  }
}

///|
pub fn stage_drawing(
  kind : @scene.ObjectKind,
  start : @scene.Point,
  end : @scene.Point,
  constrain : Bool,
) -> @scene.ObjectState {
  let mut dx = end.x - start.x
  let mut dy = end.y - start.y
  if constrain && (kind is Circle || kind is Rectangle) {
    let side = dx.abs().max(dy.abs())
    dx = (if dx < 0.0 { -1.0 } else { 1.0 }) * side
    dy = (if dy < 0.0 { -1.0 } else { 1.0 }) * side
  }
  let line = kind is Path || kind is Arrow || kind is NumberLine
  {
    ..@scene.default_state(kind),
    x: if line {
      start.x
    } else {
      start.x + dx / 2.0
    },
    y: if line {
      start.y
    } else {
      start.y + dy / 2.0
    },
    width: if line {
      dx
    } else {
      dx.abs()
    },
    height: if line {
      dy
    } else {
      dy.abs()
    },
    path: { c1: { x: dx / 3.0, y: 0.0, }, c2: { x: dx * 2.0 / 3.0, y: dy, }, },
  }
}
