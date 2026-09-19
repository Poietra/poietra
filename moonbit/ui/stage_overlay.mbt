///|
fn stage_rotation(state : @core.Any) -> @core.Any {
  @core.any(
    "rotate(" +
    string_value(state._get("rotation")) +
    " " +
    string_value(state._get("x")) +
    " " +
    string_value(state._get("y")) +
    ")",
  )
}

///|
fn stage_object_locked(scene : @core.Any, id : String) -> Bool {
  let object = scene._get("objects")._get(id)
  truthy(object) && truthy(object._get("locked"))
}

///|
fn stage_selection(
  controller : StageController,
  item : @core.Any,
) -> @react.Element {
  let object = item._get("object")
  let id : String = object._get("id").cast()
  let b = stage_bounds(controller.renderer._call("objectBounds", [item]))
  let scale = controller.scale
  let locked = stage_object_locked(controller.scene, id)
  let editable = controller.state_editing &&
    !locked &&
    controller.selected.length() == 1 &&
    controller.tool is SelectTool
  let kind = @boundary.read_object_kind(object._get("kind"))
  let resizable = editable &&
    (
      kind is Circle ||
      kind is Rectangle ||
      kind is Text ||
      kind is Equation ||
      kind is Image ||
      kind is Video
    )
  let content : Array[&@react.ReactNode] = [
    h(
      "rect",
      {
        "x": @core.any(b.x),
        "y": @core.any(b.y),
        "width": @core.any(b.width.max(1.0)),
        "height": @core.any(b.height.max(1.0)),
        "fill": @core.any("none"),
        "stroke": @core.any(if locked { "#aaa6b9" } else { "#9696eb" }),
        "strokeWidth": @core.any(scale),
        "strokeDasharray": if locked {
          @core.any("\{4.0 * scale} \{3.0 * scale}")
        } else {
          @core.undefined()
        },
      },
      [],
    ),
  ]
  if resizable {
    for
      (corner, sx, sy) in [
        ("nw", -1.0, -1.0),
        ("ne", 1.0, -1.0),
        ("se", 1.0, 1.0),
        ("sw", -1.0, 1.0),
      ] {
      let x = b.x + (sx + 1.0) * b.width / 2.0
      let y = b.y + (sy + 1.0) * b.height / 2.0
      content.push(
        h(
          "g",
          {
            "key": @core.any(corner),
            "data-transform-handle": @core.any(corner),
            "style": host_record({
              "pointerEvents": @core.any("all"),
              "cursor": @core.any(
                if corner == "nw" || corner == "se" {
                  "nwse-resize"
                } else {
                  "nesw-resize"
                },
              ),
            }),
          },
          [
            h(
              "rect",
              {
                "x": @core.any(x - 8.0 * scale),
                "y": @core.any(y - 8.0 * scale),
                "width": @core.any(16.0 * scale),
                "height": @core.any(16.0 * scale),
                "fill": @core.any("transparent"),
              },
              [],
            ),
            h(
              "rect",
              {
                "x": @core.any(x - 3.0 * scale),
                "y": @core.any(y - 3.0 * scale),
                "width": @core.any(6.0 * scale),
                "height": @core.any(6.0 * scale),
                "fill": @core.any("#181820"),
                "stroke": @core.any("#a9a7fb"),
                "strokeWidth": @core.any(scale),
              },
              [],
            ),
          ],
        ),
      )
    }
  }
  if editable {
    content.push(
      h("g", Map([]), [
        h(
          "path",
          {
            "d": @core.any("M\{b.x + b.width / 2.0} \{b.y} v\{-23.0 * scale}"),
            "stroke": @core.any("#9696eb"),
            "strokeWidth": @core.any(scale),
          },
          [],
        ),
        h(
          "g",
          {
            "data-transform-handle": @core.any("rotate"),
            "style": host_record({
              "pointerEvents": @core.any("all"),
              "cursor": @core.any("grab"),
            }),
          },
          [
            h(
              "circle",
              {
                "cx": @core.any(b.x + b.width / 2.0),
                "cy": @core.any(b.y - 25.0 * scale),
                "r": @core.any(9.0 * scale),
                "fill": @core.any("transparent"),
              },
              [],
            ),
            h(
              "circle",
              {
                "cx": @core.any(b.x + b.width / 2.0),
                "cy": @core.any(b.y - 25.0 * scale),
                "r": @core.any(4.0 * scale),
                "fill": @core.any("#181820"),
                "stroke": @core.any("#a9a7fb"),
                "strokeWidth": @core.any(scale),
              },
              [],
            ),
          ],
        ),
      ]),
    )
  }
  h(
    "g",
    {
      "key": @core.any(id),
      "data-selection-id": @core.any(id),
      "data-locked": if locked {
        @core.any(true)
      } else {
        @core.undefined()
      },
      "transform": stage_box_transform(item),
    },
    content,
  )
}

///|
fn stage_peers(controller : StageController) -> Array[&@react.ReactNode] {
  let peers : FixedArray[@core.Any] = controller.editor._get("peers").cast()
  let result : Array[&@react.ReactNode] = []
  for peer in peers {
    if @core.equal(
        peer._get("clientId"),
        controller.store._get("doc")._get("clientID"),
      ) ||
      !@core.equal(peer._get("sceneId"), @core.any(controller.scene_id)) ||
      !@core.equal(
        peer._get("compositionId"),
        @core.any(controller.composition_id),
      ) ||
      !truthy(peer._get("cursor")) {
      continue
    }
    let name : String = peer._get("name").cast()
    let cursor = peer._get("cursor")
    result.push(
      h(
        "g",
        {
          "key": peer._get("clientId"),
          "transform": @core.any(
            "translate(" +
            string_value(cursor._get("x")) +
            " " +
            string_value(cursor._get("y")) +
            ") scale(\{controller.scale})",
          ),
        },
        [
          h(
            "path",
            {
              "d": @core.any("M0 0 L0 17 L5 12 L9 21 L12 19 L8 11 L16 11 Z"),
              "fill": peer._get("color"),
              "stroke": @core.any("#15151b"),
              "strokeWidth": @core.any("1"),
            },
            [],
          ),
          h(
            "rect",
            {
              "x": @core.any("17"),
              "y": @core.any("14"),
              "width": @core.any(name.length().to_double() * 6.5 + 12.0),
              "height": @core.any("20"),
              "rx": @core.any("4"),
              "fill": peer._get("color"),
            },
            [],
          ),
          h(
            "text",
            {
              "x": @core.any("23"),
              "y": @core.any("28"),
              "fill": @core.any("#15151b"),
              "fontSize": @core.any("11"),
              "fontFamily": @core.any("Arial"),
            },
            [name],
          ),
        ],
      ),
    )
  }
  result
}
