///|
priv struct GeometryInspectorView {
  controller : InspectorController
  definition : @scene.GeometryDefinition
}

///|
let geometry_inspector_component : TypedComponent[GeometryInspectorView] = memo_typed_component(
  geometry_inspector,
)

///|
fn geometry_inspector(input : GeometryInspectorView) -> @react.Element {
  let definition = input.definition
  let controller = input.controller
  let (selected, set_selected) = @react.use_state("points/a")
  let (error, set_error) = @react.use_state("")
  let resolved = @scene.geometry_points(definition)
  let ids = resolved.keys().to_array()
  ids.sort()
  let rows : Array[(String, String)] = []
  let point_ids = definition.points.keys().to_array()
  point_ids.sort()
  for id in point_ids {
    let point = definition.points[id]
    if point.deleted != Some(true) {
      rows.push(
        (
          "points/" + id,
          (if point.kind == @scene.FreePoint { "点 " } else { "中点 " }) +
          point.label,
        ),
      )
    }
  }
  let vector_ids = definition.vectors.keys().to_array()
  vector_ids.sort()
  for id in vector_ids {
    let value = definition.vectors[id]
    if value.deleted != Some(true) {
      rows.push(("vectors/" + id, "ベクトル " + value.label))
    }
  }
  let angle_ids = definition.angles.keys().to_array()
  angle_ids.sort()
  for id in angle_ids {
    let value = definition.angles[id]
    if value.deleted != Some(true) {
      rows.push(("angles/" + id, "角度 " + value.label))
    }
  }
  let selected = if rows.any(fn(row) { row.0 == selected }) {
    selected
  } else {
    rows.get(0).map(fn(row) { row.0 }).unwrap_or("")
  }
  let parts = selected.split("/").to_array().map(fn(part) { part.to_owned() })
  let collection = parts.get(0).unwrap_or("points")
  let id = parts.get(1).unwrap_or("")
  let apply = fn(field : String, id : String, patch : @core.Any) {
    attempt(
      fn() {
        controller.update({
          "geometry": host_record(
            Map([(field, host_record(Map([(id, patch)])))]),
          ),
        })
        set_error("")
      },
      set_error,
      "数学図を変更できませんでした。",
    )
  }
  let label_field = fn(value : String) {
    component(field, { "label": @core.any("Label") }, [
      h(
        "input",
        {
          "aria-label": @core.any("Geometry element label"),
          "className": @core.any("content-input"),
          "value": @core.any(value),
          "maxLength": @core.any(100),
          "onChange": @core.any(fn(event : @core.Any) {
            apply(
              collection,
              id,
              host_record({ "label": event._get("target")._get("value") }),
            )
          }),
        },
        [],
      ),
    ])
  }
  let reference = fn(label : String, key : String, value : String) {
    component(field, { "label": @core.any(label) }, [
      h(
        "select",
        {
          "aria-label": @core.any("Geometry " + label),
          "value": @core.any(value),
          "onChange": @core.any(fn(event : @core.Any) {
            apply(
              collection,
              id,
              host_record(Map([(key, event._get("target")._get("value"))])),
            )
          }),
        },
        ids
        .map(fn(id) {
          h("option", { "key": @core.any(id), "value": @core.any(id) }, [
            definition.points[id].label,
          ])
        })
        .map(fn(node) -> &@react.ReactNode { node }),
      ),
    ])
  }
  let text = fn(value : String) {
    h(
      "p",
      {
        "className": @core.any("muted small"),
        "data-testid": @core.any("geometry-value"),
      },
      [value],
    )
  }
  let content : Array[&@react.ReactNode] = [
    h("p", { "className": @core.any("muted small") }, [
      "点をドラッグするか座標を編集すると、参照しているベクトル・中点・角度も変わります。Xは右、Yは上が正です。",
    ]),
  ]
  content.push(
    component(field, { "label": @core.any("Element") }, [
      h(
        "select",
        {
          "aria-label": @core.any("Geometry element"),
          "value": @core.any(selected),
          "onChange": @core.any(fn(event : @core.Any) {
            set_selected(event._get("target")._get("value").cast())
            set_error("")
          }),
        },
        rows.map(fn(row) -> &@react.ReactNode {
          h("option", { "key": @core.any(row.0), "value": @core.any(row.0) }, [
            row.1,
          ])
        }),
      ),
    ]),
  )
  if collection == "points" && definition.points.get(id) is Some(point) {
    content.push(label_field(point.label))
    if point.kind == @scene.FreePoint {
      content.push(
        h("div", { "className": @core.any("property-grid") }, [
          number_field(
            "X",
            "Geometry point X",
            point.x,
            fn(value) {
              apply(collection, id, host_record({ "x": @core.any(value) }))
            },
            min=-100000.0,
            max=100000.0,
          ),
          number_field(
            "Y",
            "Geometry point Y",
            point.y,
            fn(value) {
              apply(collection, id, host_record({ "y": @core.any(value) }))
            },
            min=-100000.0,
            max=100000.0,
          ),
        ]),
      )
    } else {
      content.push(reference("First point", "from", point.from.unwrap_or("")))
      content.push(reference("Second point", "to", point.to.unwrap_or("")))
      if resolved.get(id) is Some(p) {
        content.push(
          text(
            "中点：(" +
            @render.number(p.x) +
            ", " +
            @render.number(p.y) +
            ")",
          ),
        )
      }
    }
  } else if collection == "vectors" &&
    definition.vectors.get(id) is Some(vector) {
    content.push(label_field(vector.label))
    content.push(reference("From point", "from", vector.from))
    content.push(reference("To point", "to", vector.to))
    if resolved.get(vector.from) is Some(a) &&
      resolved.get(vector.to) is Some(b) {
      content.push(
        text(
          "成分：(" +
          @render.number(b.x - a.x) +
          ", " +
          @render.number(b.y - a.y) +
          ") · 長さ " +
          @render.number(@scene.point_distance(a, b)),
        ),
      )
    }
  } else if collection == "angles" && definition.angles.get(id) is Some(angle) {
    content.push(label_field(angle.label))
    content.push(reference("First point", "from", angle.from))
    content.push(reference("Vertex point", "vertex", angle.vertex))
    content.push(reference("Second point", "to", angle.to))
    if resolved.get(angle.from) is Some(a) &&
      resolved.get(angle.vertex) is Some(v) &&
      resolved.get(angle.to) is Some(b) {
      content.push(
        text(
          match @scene.geometry_angle(a, v, b) {
            Some(degrees) =>
              @render.number((degrees * 10.0).round() / 10.0) + "°"
            None =>
              "端点と頂点が重なっているため、角度は未定義です。"
          },
        ),
      )
    }
  }
  let add_point = fn(midpoint : Bool) {
    let id = @boundary.new_id("point")
    let point : @scene.GeometryPoint = {
      kind: if midpoint {
        @scene.MidpointPoint
      } else {
        @scene.FreePoint
      },
      x: 0.0,
      y: 0.0,
      from: if midpoint {
        ids.get(0)
      } else {
        None
      },
      to: if midpoint {
        ids.get(1)
      } else {
        None
      },
      label: (if midpoint { "M" } else { "P" }) +
      "\{definition.points.length() + 1}",
      deleted: None,
    }
    apply("points", id, @boundary.write_geometry_point(point))
    set_selected("points/" + id)
  }
  content.push(
    h("div", { "className": @core.any("property-grid") }, [
      inspector_button(
        "点を追加",
        "Plus",
        fn() { add_point(false) },
        disabled=definition.points.length() >= 128,
      ),
      inspector_button(
        "中点を追加",
        "Plus",
        fn() { add_point(true) },
        disabled=ids.length() < 2 || definition.points.length() >= 128,
      ),
      inspector_button(
        "ベクトルを追加",
        "Plus",
        fn() {
          let id = @boundary.new_id("vector")
          apply(
            "vectors",
            id,
            @boundary.write_geometry_vector({
              from: ids[0],
              to: ids[1],
              label: "v\{definition.vectors.length() + 1}",
              deleted: None,
            }),
          )
          set_selected("vectors/" + id)
        },
        disabled=ids.length() < 2 || definition.vectors.length() >= 128,
      ),
      inspector_button(
        "角度を追加",
        "Plus",
        fn() {
          let id = @boundary.new_id("angle")
          apply(
            "angles",
            id,
            @boundary.write_geometry_angle({
              from: ids[1],
              vertex: ids[0],
              to: ids[2],
              label: "θ\{definition.angles.length() + 1}",
              deleted: None,
            }),
          )
          set_selected("angles/" + id)
        },
        disabled=ids.length() < 3 || definition.angles.length() >= 128,
      ),
    ]),
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
  if @scene.geometry_validation_error(definition) is Some(message) {
    content.push(
      h(
        "p",
        { "role": @core.any("alert"), "className": @core.any("muted small") },
        [message],
      ),
    )
  }
  if !error.is_empty() {
    content.push(
      h(
        "p",
        { "role": @core.any("alert"), "className": @core.any("muted small") },
        [error],
      ),
    )
  }
  inspector_section("Mathematical diagram", content)
}
