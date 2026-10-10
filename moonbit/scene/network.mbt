///|
pub fn default_network() -> NetworkDefinition {
  {
    version: 1,
    nodes: {
      "a": { x: -2.0, y: -1.0, label: "A", deleted: None, },
      "b": { x: 2.0, y: -1.0, label: "B", deleted: None, },
      "c": { x: 0.0, y: 2.0, label: "C", deleted: None, },
    },
    edges: {
      "ab": {
        from: "a",
        to: "b",
        label: "",
        directed: false,
        weight: Some(1.0),
        bend: 0.0,
        deleted: None,
      },
      "bc": {
        from: "b",
        to: "c",
        label: "",
        directed: true,
        weight: Some(2.0),
        bend: 0.0,
        deleted: None,
      },
      "ca": {
        from: "c",
        to: "a",
        label: "",
        directed: true,
        weight: Some(3.0),
        bend: 0.0,
        deleted: None,
      },
    },
  }
}

///|
pub fn network_validation_error(value : NetworkDefinition) -> String? {
  if value.version != 1 ||
    value.nodes.length() > 128 ||
    value.edges.length() > 256 {
    return Some(
      "ノードは128個、辺は256個までです。バージョンは1を指定してください。",
    )
  }
  for id, node in value.nodes {
    if !geometry_id_valid(id) ||
      node.label.length() > 100 ||
      [node.x, node.y].any(fn(v) {
        v.is_nan() || v.is_inf() || v.abs() > 100000.0
      }) {
      return Some("ノードのID・ラベル・座標が不正です。")
    }
  }
  for id, edge in value.edges {
    if !geometry_id_valid(id) ||
      edge.label.length() > 100 ||
      edge.bend.is_nan() ||
      edge.bend.is_inf() ||
      edge.bend.abs() > 10.0 ||
      edge.weight
      .map(fn(v) { v.is_nan() || v.is_inf() || v.abs() > 100000.0 })
      .unwrap_or(false) {
      return Some("辺のID・ラベル・重み・曲がりが不正です。")
    }
    if edge.deleted != Some(true) &&
      [edge.from, edge.to].any(fn(id) {
        value.nodes
        .get(id)
        .map(fn(n) { n.deleted == Some(true) })
        .unwrap_or(true)
      }) {
      return Some(
        "辺が参照するノードがありません。参照している辺を先に削除してください。",
      )
    }
  }
  None
}

///|
pub fn network_texts(value : NetworkDefinition) -> Array[String] {
  let result = ["0123456789.-"]
  for _, node in value.nodes {
    if node.deleted != Some(true) {
      result.push(node.label)
    }
  }
  for _, edge in value.edges {
    if edge.deleted != Some(true) {
      result.push(edge.label)
    }
  }
  result
}

///|
pub fn network_circle_positions(
  value : NetworkDefinition,
) -> Map[String, Point] {
  let ids = value.nodes
    .keys()
    .filter(fn(id) { value.nodes[id].deleted != Some(true) })
    .to_array()
  let result : Map[String, Point] = Map([])
  for p in @math_network.circle(ids, 2.5) {
    result[p.id] = { x: p.x, y: p.y, }
  }
  result
}

///|
pub fn network_degree(
  value : NetworkDefinition,
  id : String,
) -> @math_network.Degree {
  @math_network.degree(
    id,
    value.edges
    .values()
    .filter(fn(e) { e.deleted != Some(true) })
    .map(fn(e) {
      @math_network.Edge::{ from: e.from, to: e.to, directed: e.directed, }
    })
    .to_array(),
  )
}

///|
fn interpolate_network(
  a : NetworkDefinition?,
  b : NetworkDefinition?,
  progress : Double,
  discrete : Double,
  interpolate : (Double, Double, Double) -> Double,
) -> NetworkDefinition? {
  if a is None && b is None {
    return None
  }
  let a = a.unwrap_or(default_network())
  let b = b.unwrap_or(default_network())
  let value = if discrete < 0.5 { a } else { b }
  let nodes = value.nodes.copy()
  for id, n in value.nodes {
    if a.nodes.get(id) is Some(p) &&
      b.nodes.get(id) is Some(q) &&
      p.deleted != Some(true) &&
      q.deleted != Some(true) {
      nodes[id] = {
        ..n,
        x: interpolate(p.x, q.x, progress),
        y: interpolate(p.y, q.y, progress),
      }
    }
  }
  Some({ ..value, nodes, })
}

///|
pub fn has_spatial_math(scene : Scene) -> Bool {
  scene.objects.values().any(fn(o) { o.kind == Network || o.kind == Surface }) ||
  scene.compositions
  .values()
  .any(fn(c) {
    c.states
    .values()
    .any(fn(s) { s.network is Some(_) || s.surface is Some(_) })
  })
}
