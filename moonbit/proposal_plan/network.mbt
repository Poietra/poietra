///|
fn math_value_changed(a : Value?, b : Value?) -> Bool {
  match (a, b) {
    (Some(ScalarValue(Number(a))), Some(ScalarValue(Number(b)))) => a != b
    (Some(ScalarValue(Text(a))), Some(ScalarValue(Text(b)))) => a != b
    (Some(ScalarValue(Boolean(a))), Some(ScalarValue(Boolean(b)))) => a != b
    (Some(OptionalNumberValue(a)), Some(OptionalNumberValue(b))) => a != b
    (None, None) => false
    _ => true
  }
}

///|
fn network_element_fields(element : NetworkElement) -> Map[String, Value] {
  match element {
    NodeElement(n) =>
      {
        "x": ScalarValue(Number(n.x)),
        "y": ScalarValue(Number(n.y)),
        "label": ScalarValue(Text(n.label)),
        "deleted": ScalarValue(Boolean(n.deleted == Some(true))),
      }
    EdgeElement(e) =>
      {
        "from": ScalarValue(Text(e.from)),
        "to": ScalarValue(Text(e.to)),
        "label": ScalarValue(Text(e.label)),
        "directed": ScalarValue(Boolean(e.directed)),
        "weight": OptionalNumberValue(e.weight),
        "bend": ScalarValue(Number(e.bend)),
        "deleted": ScalarValue(Boolean(e.deleted == Some(true))),
      }
  }
}

///|
fn Compiler::edit_network(
  self : Compiler,
  cid : String,
  oid : String,
  collection : String,
  id : String,
  element : NetworkElement?,
) -> Unit raise CompileError {
  let cid = self.resolve(cid, CompositionRef)
  let oid = self.resolve(oid, ObjectRef)
  let object = self.object(oid)
  self.composition(cid) |> ignore
  if object.kind != Network ||
    !["nodes", "edges"].contains(collection) ||
    id.is_empty() ||
    id.length() > 80 {
    raise CompileError("グラフ理論の図の編集対象が不正です。")
  }
  let state = self.state(cid, oid).unwrap_or(@scene.default_state(Network))
  let definition = state.network.unwrap_or(@scene.default_network())
  let previous = if collection == "nodes" {
    definition.nodes.get(id).map(fn(n) { NodeElement(n) })
  } else {
    definition.edges.get(id).map(fn(e) { EdgeElement(e) })
  }
  let next = match (collection, element) {
    ("nodes", Some(NodeElement(n))) =>
      NodeElement({ ..n, deleted: Some(false), })
    ("edges", Some(EdgeElement(e))) =>
      EdgeElement({ ..e, deleted: Some(false), })
    (_, None) =>
      match previous {
        Some(NodeElement(n)) => NodeElement({ ..n, deleted: Some(true), })
        Some(EdgeElement(e)) => EdgeElement({ ..e, deleted: Some(true), })
        None => raise CompileError("削除する要素がありません。")
      }
    _ =>
      raise CompileError(
        "要素とコレクションの種類が一致しません。",
      )
  }
  let definition = match next {
    NodeElement(n) => {
      let nodes = definition.nodes.copy()
      nodes[id] = n
      { ..definition, nodes, }
    }
    EdgeElement(e) => {
      let edges = definition.edges.copy()
      edges[id] = e
      { ..definition, edges, }
    }
  }
  // Validate the complete operation sequence in finish: an edge and its new
  // endpoints may be declared in either order, without publishing partial data.
  self.set_state(cid, oid, { ..state, network: Some(definition), })
  if self.created.contains(oid) || self.appended.contains(cid) {
    return
  }
  let base = ["compositions", cid, "states", oid, "network"]
  self.depend(base + ["version"])
  let path = base + [collection, id]
  let updated = network_element_fields(next)
  let old = previous.map(network_element_fields).unwrap_or(Map([]))
  match previous {
    None => {
      self.depend(base + [collection])
      self.emit(
        path,
        match next {
          NodeElement(n) => NetworkNodeValue(n)
          EdgeElement(e) => NetworkEdgeValue(e)
        },
      )
    }
    Some(_) =>
      for key, value in updated {
        if math_value_changed(old.get(key), Some(value)) {
          self.emit(path + [key], value)
        }
      }
  }
  self.depend(path + ["deleted"])
  let structural = element is None ||
    previous is None ||
    ["from", "to", "deleted"].any(fn(key) {
      math_value_changed(old.get(key), updated.get(key))
    })
  if structural {
    if element is None {
      // Deletion must not orphan an edge added after the proposal.
      self.depend(base)
    }
    if next is EdgeElement(e) {
      for node_id in [e.from, e.to] {
        self.depend(base + ["nodes", node_id, "deleted"])
      }
    }
  }
}
