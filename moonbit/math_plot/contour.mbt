///|
priv struct ContourPoint {
  id : Int
  x : Double
  y : Double
  value : Double?
}

///|
priv struct ContourSampler {
  program : Program
  a : Double
  b : Double
  c : Double
  breaks : Array[Double]
  roots : Map[(Int, Int), ContourPoint?]
  used_edges : Map[(Int, Int), Bool]
  edges : Array[(ContourPoint, ContourPoint)]
  mut next_id : Int
  mut evaluations : Int
  mut limited : Bool
}

///|
fn ContourSampler::value(
  self : ContourSampler,
  x : Double,
  y : Double,
) -> Double? {
  if self.evaluations >= 65536 {
    self.limited = true
    return None
  }
  self.evaluations += 1
  self.program.evaluate_at(x, y, self.a, self.b, self.c)
}

///|
fn ContourSampler::point(
  self : ContourSampler,
  x : Double,
  y : Double,
  value : Double?,
) -> ContourPoint {
  let id = self.next_id
  self.next_id += 1
  { id, x, y, value, }
}

///|
fn edge_key(a : ContourPoint, b : ContourPoint) -> (Int, Int) {
  if a.id < b.id {
    (a.id, b.id)
  } else {
    (b.id, a.id)
  }
}

///|
fn ContourSampler::find_root(
  self : ContourSampler,
  a : ContourPoint,
  b : ContourPoint,
) -> ContourPoint? {
  guard a.value is Some(fa) && b.value is Some(fb) else { return None }
  if fa == 0.0 {
    return Some(a)
  }
  if fb == 0.0 {
    return Some(b)
  }
  if (fa < 0.0) == (fb < 0.0) {
    return None
  }
  let scale = fa.abs().max(fb.abs())
  let mut low = 0.0
  let mut high = 1.0
  let negative = fa < 0.0
  let mut best = if fa.abs() <= fb.abs() {
    (a.x, a.y, fa.abs())
  } else {
    (b.x, b.y, fb.abs())
  }
  for _ in 0..<20 {
    let at = (low + high) / 2.0
    let x = a.x + (b.x - a.x) * at
    let y = a.y + (b.y - a.y) * at
    guard self.value(x, y) is Some(value) else {
      self.limited = true
      return None
    }
    if value == 0.0 {
      if x == a.x && y == a.y {
        return Some(a)
      }
      if x == b.x && y == b.y {
        return Some(b)
      }
      return Some(self.point(x, y, Some(0.0)))
    }
    if value.abs() < best.2 {
      best = (x, y, value.abs())
    }
    if (value < 0.0) == negative {
      low = at
    } else {
      high = at
    }
  }
  // A sign change at a pole or finite jump is not a root. Check residual
  // improvement relative to the bracket, keeping equation scaling irrelevant.
  if best.2 <= scale * 0.0001 {
    // Cancellation can make a root coincide with a sampled vertex within
    // floating-point precision. Keep its identity across incident edges.
    if best.0 == a.x && best.1 == a.y {
      return Some(a)
    }
    if best.0 == b.x && best.1 == b.y {
      return Some(b)
    }
    Some(self.point(best.0, best.1, Some(0.0)))
  } else {
    self.limited = true
    None
  }
}

///|
fn ContourSampler::root(
  self : ContourSampler,
  a : ContourPoint,
  b : ContourPoint,
) -> ContourPoint? {
  guard a.value is Some(fa) && b.value is Some(fb) else { return None }
  if fa == 0.0 {
    return Some(a)
  }
  if fb == 0.0 {
    return Some(b)
  }
  if (fa < 0.0) == (fb < 0.0) {
    return None
  }
  let key = edge_key(a, b)
  if self.roots.get(key) is Some(root) {
    return root
  }
  let result = self.find_root(a, b)
  self.roots[key] = result
  result
}

///|
fn ContourSampler::line(
  self : ContourSampler,
  a : ContourPoint,
  b : ContourPoint,
  scale : Double,
) -> Unit {
  if a.id == b.id || (a.x == b.x && a.y == b.y) {
    return
  }
  let key = edge_key(a, b)
  if self.used_edges.contains(key) {
    return
  }
  for value in self.breaks {
    if value >= a.x.min(b.x) && value <= a.x.max(b.x) {
      return
    }
  }
  if self.edges.length() >= 8192 {
    self.limited = true
    return
  }
  // Reject an unresolved interior rather than bridging undefined branches.
  guard self.value((a.x + b.x) / 2.0, (a.y + b.y) / 2.0) is Some(middle) else {
    self.limited = true
    return
  }
  if middle.abs() > scale * 0.25 {
    self.limited = true
    return
  }
  self.used_edges[key] = true
  self.edges.push((a, b))
}

///|
fn ContourSampler::triangle(
  self : ContourSampler,
  a : ContourPoint,
  b : ContourPoint,
  c : ContourPoint,
) -> Unit {
  guard a.value is Some(fa) && b.value is Some(fb) && c.value is Some(fc) else {
    return
  }
  if fa == 0.0 && fb == 0.0 && fc == 0.0 {
    // A zero-valued area cannot be represented by a curve.
    self.limited = true
    return
  }
  if (fa > 0.0 && fb > 0.0 && fc > 0.0) || (fa < 0.0 && fb < 0.0 && fc < 0.0) {
    return
  }
  let scale = fa.abs().max(fb.abs()).max(fc.abs())
  let roots : Array[ContourPoint] = []
  let mut zero_edge = false
  for (start, end) in [(a, b), (b, c), (c, a)] {
    if start.value == Some(0.0) && end.value == Some(0.0) {
      self.line(start, end, scale)
      zero_edge = true
    } else if self.root(start, end) is Some(root) &&
      !roots.any(fn(point) { point.id == root.id }) {
      roots.push(root)
    }
  }
  if !zero_edge && roots.length() == 2 {
    self.line(roots[0], roots[1], scale)
  }
}

///|
fn contour_segments(
  edges : Array[(ContourPoint, ContourPoint)],
  viewport : Viewport,
) -> Array[Segment] {
  let adjacent : Map[Int, Array[Int]] = Map([])
  for index, (a, b) in edges {
    for point in [a, b] {
      match adjacent.get(point.id) {
        Some(indices) => indices.push(index)
        None => adjacent[point.id] = [index]
      }
    }
  }
  let visited = Array::make(edges.length(), false)
  let result : Array[Segment] = []
  let walk = fn(start : ContourPoint, first : Int) {
    let mut point = start
    let mut index = first
    while !visited[index] {
      visited[index] = true
      let (a, b) = edges[index]
      let next = if point.id == a.id { b } else { a }
      let from = viewport.point(point.x, point.y)
      let to = viewport.point(next.x, next.y)
      result.push({ x0: from.0, y0: from.1, x1: to.0, y1: to.1, })
      let neighbors = adjacent[next.id]
      if neighbors.length() != 2 {
        break
      }
      let following = if !visited[neighbors[0]] {
        neighbors[0]
      } else {
        neighbors[1]
      }
      if visited[following] {
        break
      }
      index = following
      point = next
    }
  }
  // Open branches and junctions first, then remaining closed components.
  // Shared root identities keep Write continuous within each component.
  for index, (a, b) in edges {
    if !visited[index] {
      if adjacent[a.id].length() != 2 {
        walk(a, index)
      } else if adjacent[b.id].length() != 2 {
        walk(b, index)
      }
    }
  }
  for index, (a, _) in edges {
    if !visited[index] {
      walk(a, index)
    }
  }
  result
}

///|
/// Sample an equation's zero set in mathematical coordinates. A center sample
/// splits each grid cell into four triangles, resolving diagonal ambiguity and
/// detecting closed components around a center that corner signs alone miss.
pub fn plot_implicit(
  program : Program,
  viewport : Viewport,
  a : Double,
  b : Double,
  c : Double,
  breaks : Array[Double],
) -> Plot {
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
    ] +
    breaks {
    if value.is_nan() || value.is_inf() {
      return { segments: [], limited: false, evaluations: 0, }
    }
  }
  if breaks.length() > 32 {
    return { segments: [], limited: true, evaluations: 0, }
  }
  if viewport.x_max <= viewport.x_min ||
    viewport.y_max <= viewport.y_min ||
    viewport.width <= 0.0 ||
    viewport.height <= 0.0 {
    return { segments: [], limited: false, evaluations: 0, }
  }
  let sampler : ContourSampler = {
    program,
    a,
    b,
    c,
    breaks,
    roots: Map([]),
    used_edges: Map([]),
    edges: [],
    next_id: 0,
    evaluations: 0,
    limited: false,
  }
  let columns = (viewport.width / 4.0).ceil().min(128.0).max(16.0).to_int()
  let rows = (viewport.height / 4.0).ceil().min(128.0).max(16.0).to_int()
  let x_at = fn(at : Double) {
    viewport.x_min +
    (viewport.x_max - viewport.x_min) * at / columns.to_double()
  }
  let y_at = fn(at : Double) {
    viewport.y_min + (viewport.y_max - viewport.y_min) * at / rows.to_double()
  }
  let vertices = Array::makei((columns + 1) * (rows + 1), fn(index) {
    let x = x_at((index % (columns + 1)).to_double())
    let y = y_at((index / (columns + 1)).to_double())
    sampler.point(x, y, sampler.value(x, y))
  })
  for row = 0; row < rows; row = row + 1 {
    for column = 0; column < columns; column = column + 1 {
      if sampler.evaluations >= 65536 || sampler.edges.length() >= 8192 {
        sampler.limited = true
        break
      }
      let index = row * (columns + 1) + column
      let corners = [
        vertices[index],
        vertices[index + 1],
        vertices[index + columns + 2],
        vertices[index + columns + 1],
      ]
      let x = x_at(column.to_double() + 0.5)
      let y = y_at(row.to_double() + 0.5)
      let center = sampler.point(x, y, sampler.value(x, y))
      for i in 0..<4 {
        sampler.triangle(corners[i], corners[(i + 1) % 4], center)
      }
    }
  }
  {
    segments: contour_segments(sampler.edges, viewport),
    limited: sampler.limited,
    evaluations: sampler.evaluations,
  }
}
