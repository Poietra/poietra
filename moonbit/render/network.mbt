///|
pub fn network_geometry(
  state : @scene.ObjectState,
  progress : Double,
) -> DiagramGeometry {
  if unit(progress) == 0.0 {
    return { curves: [], labels: [], limited: false, }
  }
  let value = state.network.unwrap_or(@scene.default_network())
  let scale = @scene.geometry_unit(state)
  let curves : Array[DiagramCurve] = []
  let labels : Array[GraphLabel] = []
  let ids = value.edges.keys().to_array()
  ids.sort()
  for id in ids {
    let edge = value.edges[id]
    if edge.deleted == Some(true) {
      continue
    }
    guard value.nodes.get(edge.from) is Some(from) &&
      value.nodes.get(edge.to) is Some(to) &&
      from.deleted != Some(true) &&
      to.deleted != Some(true) else {
      continue
    }
    let ax = from.x * scale
    let ay = -from.y * scale
    let bx = to.x * scale
    let by = -to.y * scale
    let length = @math.hypot(bx - ax, by - ay)
    let is_loop = edge.from == edge.to
    if !is_loop && length < 1.0e-9 {
      continue
    }
    let control_x = if is_loop {
      ax + 35.0 + edge.bend * scale
    } else {
      (ax + bx) / 2.0 - (by - ay) / length * edge.bend * scale
    }
    let control_y = if is_loop {
      ay - 40.0
    } else {
      (ay + by) / 2.0 + (bx - ax) / length * edge.bend * scale
    }
    let start_length = @math.hypot(control_x - ax, control_y - ay).max(1.0e-9)
    let end_length = @math.hypot(bx - control_x, by - control_y).max(1.0e-9)
    let ex = if is_loop {
      ax + 8.0
    } else {
      bx - (bx - control_x) / end_length * 10.0
    }
    let ey = if is_loop {
      ay - 6.0
    } else {
      by - (by - control_y) / end_length * 10.0
    }
    let ux = if is_loop { -0.7 } else { (bx - control_x) / end_length }
    let uy = if is_loop { 0.7 } else { (by - control_y) / end_length }
    let path = if is_loop {
      "M\{number(ax-8.0)} \{number(ay-6.0)} C\{number(ax-35.0-edge.bend*scale)} \{number(control_y)} \{number(control_x)} \{number(control_y)} \{number(ex)} \{number(ey)}"
    } else {
      "M\{number(ax+(control_x-ax)/start_length*10.0)} \{number(ay+(control_y-ay)/start_length*10.0)} Q\{number(control_x)} \{number(control_y)} \{number(ex)} \{number(ey)}"
    }
    let head = if edge.directed {
      " M\{number(ex-ux*9.0-uy*4.0)} \{number(ey-uy*9.0+ux*4.0)} L\{number(ex)} \{number(ey)} L\{number(ex-ux*9.0+uy*4.0)} \{number(ey-uy*9.0-ux*4.0)}"
    } else {
      ""
    }
    curves.push({
      id: "edges/" + id,
      path: path + head,
      fill: None,
      stroke: None,
    })
    labels.push({
      x: if is_loop {
        ax + 8.0
      } else {
        (ax + 2.0 * control_x + bx) / 4.0 + 6.0
      },
      y: if is_loop {
        control_y
      } else {
        (ay + 2.0 * control_y + by) / 4.0 - 6.0
      },
      text: edge.label +
      edge.weight
      .map(fn(w) { (if edge.label.is_empty() { "" } else { " " }) + number(w) })
      .unwrap_or(""),
    })
  }
  let ids = value.nodes.keys().to_array()
  ids.sort()
  for id in ids {
    let node = value.nodes[id]
    if node.deleted == Some(true) {
      continue
    }
    let x = node.x * scale
    let y = -node.y * scale
    curves.push({
      id: "nodes/" + id,
      path: "M\{number(x+10.0)} \{number(y)} A10 10 0 1 1 \{number(x-10.0)} \{number(y)} A10 10 0 1 1 \{number(x+10.0)} \{number(y)} Z",
      fill: Some(state.fill),
      stroke: None,
    })
    labels.push({ x: x + 14.0, y: y - 12.0, text: node.label, })
  }
  {
    curves,
    labels,
    limited: @scene.network_validation_error(value) is Some(_),
  }
}
