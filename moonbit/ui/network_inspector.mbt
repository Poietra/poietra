///|
priv struct NetworkInspectorView {
  controller : InspectorController
  definition : @scene.NetworkDefinition
}

///|
let network_inspector_component : TypedComponent[NetworkInspectorView] = memo_typed_component(
  network_inspector,
)

///|
fn network_inspector(input : NetworkInspectorView) -> @react.Element {
  let value = input.definition
  let controller = input.controller
  let (selected, set_selected) = @react.use_state("nodes/a")
  let (error, set_error) = @react.use_state("")
  let ids = value.nodes
    .keys()
    .filter(fn(id) { value.nodes[id].deleted != Some(true) })
    .to_array()
  ids.sort()
  let edges = value.edges
    .keys()
    .filter(fn(id) { value.edges[id].deleted != Some(true) })
    .to_array()
  edges.sort()
  let rows = ids.map(fn(id) {
      ("nodes/" + id, "ノード " + value.nodes[id].label)
    }) +
    edges.map(fn(id) {
      (
        "edges/" + id,
        "辺 " +
        (if value.edges[id].label.is_empty() {
          id
        } else {
          value.edges[id].label
        }),
      )
    })
  let selected = if rows.any(fn(row) { row.0 == selected }) {
    selected
  } else {
    rows.get(0).map(fn(row) { row.0 }).unwrap_or("")
  }
  let pieces = selected.split("/").to_array().map(fn(s) { s.to_owned() })
  let collection = pieces.get(0).unwrap_or("nodes")
  let id = pieces.get(1).unwrap_or("")
  let apply = fn(collection : String, id : String, patch : @core.Any) {
    attempt(
      fn() {
        controller.update({
          "network": host_record(
            Map([(collection, host_record(Map([(id, patch)])))]),
          ),
        })
        set_error("")
      },
      set_error,
      "グラフを変更できませんでした。",
    )
  }
  let label_field = fn(label : String) {
    component(field, { "label": @core.any("Label") }, [
      h(
        "input",
        {
          "aria-label": @core.any("Network element label"),
          "className": @core.any("content-input"),
          "value": @core.any(label),
          "maxLength": @core.any(100),
          "onChange": @core.any(fn(e : @core.Any) {
            apply(
              collection,
              id,
              host_record({ "label": e._get("target")._get("value") }),
            )
          }),
        },
        [],
      ),
    ])
  }
  let reference = fn(label : String, key : String, current : String) {
    component(field, { "label": @core.any(label) }, [
      select_input(
        "Network " + label,
        current,
        fn(selected_value : String) {
          apply(
            collection,
            id,
            host_record(Map([(key, @core.any(selected_value))])),
          )
        },
        ids.map(fn(id) { select_choice(id, value.nodes[id].label) }),
        disabled=!controller.can_edit(),
      ),
    ])
  }
  let content : Array[&@react.ReactNode] = [
    h("p", { "className": @core.any("muted small") }, [
      "ノードをドラッグすると、接続している辺が追従します。自己ループ・平行辺も作れます。",
    ]),
    component(field, { "label": @core.any("Element") }, [
      select_input(
        "Network element",
        selected,
        fn(selected_value : String) {
          set_selected(selected_value)
          set_error("")
        },
        rows.map(fn(row) { select_choice(row.0, row.1) }),
        disabled=!controller.can_edit(),
      ),
    ]),
  ]
  if collection == "nodes" && value.nodes.get(id) is Some(node) {
    content.push(label_field(node.label))
    content.push(
      h("div", { "className": @core.any("property-grid") }, [
        number_field(
          "X",
          "Network node X",
          node.x,
          fn(v) { apply(collection, id, host_record({ "x": @core.any(v) })) },
          min=-100000.0,
          max=100000.0,
        ),
        number_field(
          "Y",
          "Network node Y",
          node.y,
          fn(v) { apply(collection, id, host_record({ "y": @core.any(v) })) },
          min=-100000.0,
          max=100000.0,
        ),
      ]),
    )
    let degree = @scene.network_degree(value, id)
    content.push(
      h(
        "p",
        {
          "data-testid": @core.any("network-degree"),
          "className": @core.any("muted small"),
        },
        [
          "入次数 \{degree.incoming} · 出次数 \{degree.outgoing} · 無向の次数 \{degree.undirected}",
        ],
      ),
    )
  } else if value.edges.get(id) is Some(edge) {
    content.push(label_field(edge.label))
    content.push(reference("From node", "from", edge.from))
    content.push(reference("To node", "to", edge.to))
    for
      (label, checked, change) in [
        (
          "Directed edge",
          edge.directed,
          fn(v : Bool) {
            apply(collection, id, host_record({ "directed": @core.any(v) }))
          },
        ),
        (
          "Weighted edge",
          edge.weight is Some(_),
          fn(v : Bool) {
            apply(
              collection,
              id,
              host_record({
                "weight": if v {
                  @core.any(1.0)
                } else {
                  @core.null()
                },
              }),
            )
          },
        ),
      ] {
      content.push(
        h("label", { "className": @core.any("check-row") }, [
          h(
            "input",
            {
              "type": @core.any("checkbox"),
              "aria-label": @core.any("Network " + label),
              "checked": @core.any(checked),
              "onChange": @core.any(fn(e : @core.Any) {
                change(e._get("target")._get("checked").cast())
              }),
            },
            [],
          ),
          label,
        ]),
      )
    }
    if edge.weight is Some(weight) {
      content.push(
        number_field(
          "Weight",
          "Network edge weight",
          weight,
          fn(v) {
            apply(collection, id, host_record({ "weight": @core.any(v) }))
          },
          min=-100000.0,
          max=100000.0,
        ),
      )
    }
    content.push(
      number_field(
        "Bend",
        "Network edge bend",
        edge.bend,
        fn(v) { apply(collection, id, host_record({ "bend": @core.any(v) })) },
        min=-10.0,
        max=10.0,
      ),
    )
  }
  content.push(
    h("div", { "className": @core.any("property-grid") }, [
      inspector_button(
        "ノードを追加",
        "Plus",
        fn() {
          let id = @boundary.new_id("node")
          apply(
            "nodes",
            id,
            @boundary.write_network_node({
              x: 0.0,
              y: 0.0,
              label: "N\{value.nodes.length()+1}",
              deleted: None,
            }),
          )
          set_selected("nodes/" + id)
        },
        disabled=value.nodes.length() >= 128,
      ),
      inspector_button(
        "辺を追加",
        "Plus",
        fn() {
          let id = @boundary.new_id("edge")
          apply(
            "edges",
            id,
            @boundary.write_network_edge({
              from: ids[0],
              to: ids.get(1).unwrap_or(ids[0]),
              label: "",
              directed: false,
              weight: None,
              bend: 0.0,
              deleted: None,
            }),
          )
          set_selected("edges/" + id)
        },
        disabled=ids.is_empty() || value.edges.length() >= 256,
      ),
    ]),
  )
  content.push(
    inspector_button(
      "円形に配置",
      "Circle",
      fn() {
        let positions = @scene.network_circle_positions(value)
        let patches = host_record(Map([]))
        for id, p in positions {
          patches._set(
            id,
            host_record({ "x": @core.any(p.x), "y": @core.any(p.y) }),
          )
        }
        attempt(
          fn() {
            controller.update({ "network": host_record({ "nodes": patches }) })
            set_error("")
          },
          set_error,
          "ノードを配置できませんでした。",
        )
      },
      disabled=ids.is_empty(),
    ),
  )
  if !id.is_empty() {
    content.push(
      inspector_button(
        "この要素を削除",
        "Trash2",
        fn() {
          apply(collection, id, host_record({ "deleted": @core.any(true) }))
        },
        class_name="text-button",
      ),
    )
  }
  if !error.is_empty() {
    content.push(
      h(
        "p",
        {
          "role": @core.any("alert"),
          "className": @core.any("error-text small"),
        },
        [error],
      ),
    )
  }
  if @scene.network_validation_error(value) is Some(message) {
    content.push(
      h(
        "p",
        {
          "role": @core.any("alert"),
          "className": @core.any("error-text small"),
        },
        [message],
      ),
    )
  }
  inspector_section("Graph network", content)
}
