///|
/// Column vectors, in the same order as SVG/Canvas matrix(a,b,c,d,e,f).
pub fn Affine::identity() -> Affine {
  { a: 1.0, b: 0.0, c: 0.0, d: 1.0, e: 0.0, f: 0.0, }
}

///|
/// Apply child first, then self. Keep the full matrix: rotated nonuniform
/// scales can produce shear, which position/rotation/size cannot represent.
pub fn Affine::compose(self : Affine, child : Affine) -> Affine {
  {
    a: self.a * child.a + self.c * child.b,
    b: self.b * child.a + self.d * child.b,
    c: self.a * child.c + self.c * child.d,
    d: self.b * child.c + self.d * child.d,
    e: self.a * child.e + self.c * child.f + self.e,
    f: self.b * child.e + self.d * child.f + self.f,
  }
}

///|
pub fn Affine::point(self : Affine, point : Point) -> Point {
  {
    x: self.a * point.x + self.c * point.y + self.e,
    y: self.b * point.x + self.d * point.y + self.f,
  }
}

///|
pub fn Affine::vector(self : Affine, point : Point) -> Point {
  {
    x: self.a * point.x + self.c * point.y,
    y: self.b * point.x + self.d * point.y,
  }
}

///|
pub fn Affine::inverse(self : Affine) -> Affine? {
  let determinant = self.a * self.d - self.b * self.c
  let scale = (self.a.abs() + self.b.abs()) * (self.c.abs() + self.d.abs())
  if determinant.is_nan() ||
    determinant.is_inf() ||
    determinant.abs() <= scale * 1.0e-12 ||
    determinant == 0.0 {
    return None
  }
  let a = self.d / determinant
  let b = -self.b / determinant
  let c = -self.c / determinant
  let d = self.a / determinant
  let result : Affine = {
    a,
    b,
    c,
    d,
    e: -(a * self.e + c * self.f),
    f: -(b * self.e + d * self.f),
  }
  if [result.a, result.b, result.c, result.d, result.e, result.f].any(fn(v) {
      v.is_nan() || v.is_inf()
    }) {
    None
  } else {
    Some(result)
  }
}

///|
/// Geometry dimensions are independent of the local transform. Anchor (0,0)
/// preserves the old origin, including start-origin paths and centred shapes.
pub fn ObjectState::local_matrix(self : ObjectState) -> Affine {
  let angle = self.rotation * @math.PI / 180.0
  let cosine = @math.cos(angle)
  let sine = @math.sin(angle)
  let sx = self.scaleX.unwrap_or(1.0)
  let sy = self.scaleY.unwrap_or(1.0)
  let shear = self.shear.unwrap_or(0.0)
  let a = cosine * sx
  let b = sine * sx
  let c = cosine * shear - sine * sy
  let d = sine * shear + cosine * sy
  let ax = self.anchorX.unwrap_or(0.0)
  let ay = self.anchorY.unwrap_or(0.0)
  { a, b, c, d, e: self.x - a * ax - c * ay, f: self.y - b * ax - d * ay, }
}

///|
pub fn ObjectState::has_transform(self : ObjectState) -> Bool {
  self.anchorX.unwrap_or(0.0) != 0.0 ||
  self.anchorY.unwrap_or(0.0) != 0.0 ||
  self.scaleX.unwrap_or(1.0) != 1.0 ||
  self.scaleY.unwrap_or(1.0) != 1.0 ||
  self.shear.unwrap_or(0.0) != 0.0
}

///|
/// QR decomposition retains reflection and shear when changing coordinate
/// systems. A singular child is valid; only a singular parent blocks reparenting.
pub fn ObjectState::with_matrix(
  self : ObjectState,
  matrix : Affine,
) -> ObjectState {
  let sx = @math.hypot(matrix.a, matrix.b)
  let angle = if sx > 0.0 {
    @math.atan2(matrix.b, matrix.a)
  } else {
    @math.atan2(-matrix.c, matrix.d)
  }
  let cosine = @math.cos(angle)
  let sine = @math.sin(angle)
  let position = matrix.point({
    x: self.anchorX.unwrap_or(0.0),
    y: self.anchorY.unwrap_or(0.0),
  })
  {
    ..self,
    x: position.x,
    y: position.y,
    rotation: angle * 180.0 / @math.PI,
    scaleX: Some(sx),
    scaleY: Some(-sine * matrix.c + cosine * matrix.d),
    shear: Some(cosine * matrix.c + sine * matrix.d),
  }
}

///|
pub struct Hierarchy {
  parents : Map[String, String]
  order : Array[String]
}

///|
/// Keep authored links intact. Concurrent reparenting can create a cycle; every
/// replica ignores the edge of its lexically smallest ID until the cycle is fixed.
/// Missing parents also resolve as roots. Neither case mutates shared data.
pub fn prepare_hierarchy(objects : Array[SceneObject]) -> Hierarchy {
  let ids : Set[String] = Set([])
  for object in objects {
    ids.add(object.id)
  }
  let parents : Map[String, String] = Map([])
  for object in objects {
    if object.parentId is Some(parent) && ids.contains(parent) {
      parents[object.id] = parent
    }
  }
  let visited : Set[String] = Set([])
  for object in objects {
    let path : Array[String] = []
    let positions : Map[String, Int] = Map([])
    let mut current = Some(object.id)
    while current is Some(id) && !visited.contains(id) {
      if positions.get(id) is Some(start) {
        let mut cut = id
        for index = start; index < path.length(); index = index + 1 {
          if path[index] < cut {
            cut = path[index]
          }
        }
        parents.remove(cut)
        break
      }
      positions[id] = path.length()
      path.push(id)
      current = parents.get(id)
    }
    for id in path {
      visited.add(id)
    }
  }
  let done : Set[String] = Set([])
  let order : Array[String] = []
  for object in objects {
    let path : Array[String] = []
    let mut current = Some(object.id)
    while current is Some(id) && !done.contains(id) {
      path.push(id)
      current = parents.get(id)
    }
    while path.pop() is Some(id) {
      done.add(id)
      order.push(id)
    }
  }
  { parents, order, }
}

///|
pub fn Hierarchy::matrices(
  self : Hierarchy,
  states : Map[String, ObjectState],
) -> Map[String, Affine] {
  let result : Map[String, Affine] = Map([])
  for id in self.order {
    let parent = (match self.parents.get(id) {
      Some(parent) => result.get(parent)
      None => None
    }).unwrap_or(Affine::identity())
    result[id] = match states.get(id) {
      Some(state) => parent.compose(state.local_matrix())
      None => parent
    }
  }
  result
}

///|
/// Largest singular value of the linear transform: a bound on pixel enlargement
/// independent of translation and screen-space rotation.
pub fn Affine::max_scale(self : Affine) -> Double {
  (
    @math.hypot(self.a + self.d, self.b - self.c) +
    @math.hypot(self.a - self.d, self.b + self.c)
  ) /
  2.0
}
