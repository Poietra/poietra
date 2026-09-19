///|
pub(all) struct Placement {
  x : Double
  y : Double
  rotation : Double
}

///|
pub(all) struct Rectangle {
  x : Double
  y : Double
  width : Double
  height : Double
}

///|
pub(all) struct Resize {
  x : Double
  y : Double
  width : Double
  height : Double
  font_size : Double?
}

///|
pub fn rotate(point : @scene.Point, degrees : Double) -> @scene.Point {
  let angle = degrees * @math.PI / 180.0
  let c = @math.cos(angle)
  let s = @math.sin(angle)
  { x: point.x * c - point.y * s, y: point.x * s + point.y * c, }
}

///|
pub fn world_to_local(point : @scene.Point, state : Placement) -> @scene.Point {
  rotate({ x: point.x - state.x, y: point.y - state.y, }, -state.rotation)
}

///|
pub fn local_to_world(point : @scene.Point, state : Placement) -> @scene.Point {
  let rotated = rotate(point, state.rotation)
  { x: rotated.x + state.x, y: rotated.y + state.y, }
}

///|
pub fn point_in_bounds(
  point : @scene.Point,
  bounds : Rectangle,
  state : Placement,
) -> Bool {
  let relative = world_to_local(point, state)
  let left = bounds.x - state.x
  let top = bounds.y - state.y
  relative.x >= left &&
  relative.x <= left + bounds.width &&
  relative.y >= top &&
  relative.y <= top + bounds.height
}

///|
pub fn rectangle_from_points(a : @scene.Point, b : @scene.Point) -> Rectangle {
  {
    x: a.x.min(b.x),
    y: a.y.min(b.y),
    width: (b.x - a.x).abs(),
    height: (b.y - a.y).abs(),
  }
}

///|
pub fn rectangle_contains_bounds(
  rectangle : Rectangle,
  bounds : Rectangle,
  state : Placement,
) -> Bool {
  for
    (x, y) in [
      (bounds.x, bounds.y),
      (bounds.x + bounds.width, bounds.y),
      (bounds.x, bounds.y + bounds.height),
      (bounds.x + bounds.width, bounds.y + bounds.height),
    ] {
    let point = local_to_world({ x: x - state.x, y: y - state.y, }, state)
    if point.x < rectangle.x ||
      point.x > rectangle.x + rectangle.width ||
      point.y < rectangle.y ||
      point.y > rectangle.y + rectangle.height {
      return false
    }
  }
  true
}

///|
pub fn resize_from_corner(
  state : @scene.ObjectState,
  width : Double,
  height : Double,
  corner : String,
  delta : @scene.Point,
  preserve_aspect : Bool,
  text : Bool,
) -> Resize {
  let relative = if state.has_transform() {
    match state.local_matrix().inverse() {
      Some(inverse) => inverse.vector(delta)
      None => { x: 0.0, y: 0.0, }
    }
  } else {
    rotate(delta, -state.rotation)
  }
  let sign : @scene.Point = match corner {
    "nw" => { x: -1.0, y: -1.0, }
    "ne" => { x: 1.0, y: -1.0, }
    "sw" => { x: -1.0, y: 1.0, }
    _ => { x: 1.0, y: 1.0, }
  }
  let width = width.max(1.0)
  let height = height.max(1.0)
  let mut next_width = (width + relative.x * sign.x).max(1.0)
  let mut next_height = (height + relative.y * sign.y).max(1.0)
  let mut ratio = 1.0
  if text || preserve_aspect {
    ratio = if text {
      1.0 +
      (relative.x * sign.x * width + relative.y * sign.y * height) /
      (width * width + height * height)
    } else if (relative.x / width).abs() > (relative.y / height).abs() {
      next_width / width
    } else {
      next_height / height
    }
    let lower = if text {
      8.0 / state.fontSize.max(1.0)
    } else {
      (1.0 / width).max(1.0 / height)
    }
    let upper = if text {
      400.0 / state.fontSize.max(1.0)
    } else {
      (16000.0 / width).min(16000.0 / height)
    }
    ratio = lower.max(upper.min(ratio))
    next_width = width * ratio
    next_height = height * ratio
  } else {
    next_width = next_width.min(16000.0)
    next_height = next_height.min(16000.0)
  }
  let center = state
    .local_matrix()
    .vector({
      x: sign.x * (next_width - width) / 2.0,
      y: sign.y * (next_height - height) / 2.0,
    })
  {
    x: state.x + center.x,
    y: state.y + center.y,
    width: if text {
      state.width * ratio
    } else {
      next_width
    },
    height: if text {
      state.height * ratio
    } else {
      next_height
    },
    font_size: if text {
      Some(state.fontSize * ratio)
    } else {
      None
    },
  }
}

///|
pub fn rotation_from_pointer(
  state : Placement,
  start : @scene.Point,
  at : @scene.Point,
  snap : Bool,
) -> Double {
  let a = @math.atan2(start.y - state.y, start.x - state.x)
  let b = @math.atan2(at.y - state.y, at.x - state.x)
  let mut rotation = state.rotation +
    @math.atan2(@math.sin(b - a), @math.cos(b - a)) * 180.0 / @math.PI
  if snap {
    rotation = @math.floor(rotation / 15.0 + 0.5) * 15.0
  }
  ((rotation + 180.0) % 360.0 + 360.0) % 360.0 - 180.0
}

///|
pub fn point_in_matrix_bounds(
  point : @scene.Point,
  bounds : Rectangle,
  origin : @scene.Point,
  matrix : @scene.Affine,
) -> Bool {
  guard matrix.inverse() is Some(inverse) else { return false }
  let point = inverse.point(point)
  point.x >= bounds.x - origin.x &&
  point.x <= bounds.x - origin.x + bounds.width &&
  point.y >= bounds.y - origin.y &&
  point.y <= bounds.y - origin.y + bounds.height
}

///|
pub fn matrix_bounds(
  bounds : Rectangle,
  origin : @scene.Point,
  matrix : @scene.Affine,
) -> Rectangle {
  let corner = matrix.point({ x: bounds.x - origin.x, y: bounds.y - origin.y, })
  let mut left = corner.x
  let mut right = corner.x
  let mut top = corner.y
  let mut bottom = corner.y
  for
    (x, y) in [
      (bounds.x + bounds.width, bounds.y),
      (bounds.x, bounds.y + bounds.height),
      (bounds.x + bounds.width, bounds.y + bounds.height),
    ] {
    let point = matrix.point({ x: x - origin.x, y: y - origin.y, })
    left = left.min(point.x)
    right = right.max(point.x)
    top = top.min(point.y)
    bottom = bottom.max(point.y)
  }
  { x: left, y: top, width: right - left, height: bottom - top, }
}

///|
pub fn rectangle_contains_matrix(
  rectangle : Rectangle,
  bounds : Rectangle,
  origin : @scene.Point,
  matrix : @scene.Affine,
) -> Bool {
  let bounds = matrix_bounds(bounds, origin, matrix)
  bounds.x >= rectangle.x &&
  bounds.y >= rectangle.y &&
  bounds.x + bounds.width <= rectangle.x + rectangle.width &&
  bounds.y + bounds.height <= rectangle.y + rectangle.height
}
