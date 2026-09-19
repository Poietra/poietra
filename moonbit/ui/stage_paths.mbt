///|
fn stage_paths(controller : StageController) -> Array[&@react.ReactNode] {
  let result : Array[&@react.ReactNode] = []
  if !controller.can_edit || controller.selected.length() != 1 {
    return result
  }
  let id = controller.selected[0]
  let object = controller.scene._get("objects")._get(id)
  if !truthy(object) {
    return result
  }
  let selection = controller.editor._get("selection")
  let transition = if selection._get("kind").cast() == "transition" {
    controller.scene._get("transitions")._get(selection._get("id").cast())
  } else {
    @core.undefined()
  }
  let scale = controller.scale
  let locked = truthy(object._get("locked"))
  if truthy(transition) && truthy(controller.editor._get("pathEditing")) {
    let track = transition._get("tracks")._get(id)
    let from = @boundary.state_for(
      controller.scene,
      transition._get("fromId").cast(),
      id,
    )
    let to = @boundary.state_for(
      controller.scene,
      transition._get("toId").cast(),
      id,
    )
    if truthy(track) && truthy(track._get("path")) && truthy(from) && truthy(to) {
      let track = @boundary.read_track(track)
      if track.path is Some(path) {
        let from = stage_placement(from)
        let to = stage_placement(to)
        let nodes : Array[&@react.ReactNode] = [
          h(
            "path",
            {
              "d": @core.any(
                "M\{from.x} \{from.y} C\{path.c1.x} \{path.c1.y} \{path.c2.x} \{path.c2.y} \{to.x} \{to.y}",
              ),
              "strokeDasharray": @core.any("\{5.0 * scale} \{4.0 * scale}"),
            },
            [],
          ),
          h(
            "path",
            {
              "d": @core.any(
                "M\{from.x} \{from.y} L\{path.c1.x} \{path.c1.y} M\{to.x} \{to.y} L\{path.c2.x} \{path.c2.y}",
              ),
              "opacity": @core.any("0.7"),
            },
            [],
          ),
        ]
        if !locked {
          for (name, point) in [("c1", path.c1), ("c2", path.c2)] {
            nodes.push(
              h(
                "circle",
                {
                  "key": @core.any(name),
                  "data-path-handle": @core.any(name),
                  "cx": @core.any(point.x),
                  "cy": @core.any(point.y),
                  "r": @core.any(5.0 * scale),
                  "fill": @core.any("#a8a6ff"),
                  "stroke": @core.any("#181820"),
                  "strokeWidth": @core.any(1.5 * scale),
                  "className": @core.any("bezier-handle"),
                },
                [],
              ),
            )
          }
        }
        result.push(
          h(
            "g",
            {
              "fill": @core.any("none"),
              "stroke": @core.any("#9292e7"),
              "strokeWidth": @core.any(scale),
            },
            nodes,
          ),
        )
      }
    }
  }
  if !truthy(transition) &&
    controller.state_editing &&
    @boundary.read_object_kind(object._get("kind")) is Path {
    let stored = @boundary.state_for(
      controller.scene,
      controller.composition_id,
      id,
    )
    if truthy(stored) {
      let state = @boundary.read_object_state(stored)
      let path = state.path
      let nodes : Array[&@react.ReactNode] = [
        h(
          "path",
          {
            "d": @core.any(
              "M\{state.x} \{state.y} L\{state.x + path.c1.x} \{state.y + path.c1.y} M\{state.x + state.width} \{state.y + state.height} L\{state.x + path.c2.x} \{state.y + path.c2.y}",
            ),
            "fill": @core.any("none"),
          },
          [],
        ),
      ]
      if !locked {
        for (name, point) in [("c1", path.c1), ("c2", path.c2)] {
          nodes.push(
            h(
              "circle",
              {
                "key": @core.any(name),
                "data-path-handle": @core.any(name),
                "cx": @core.any(state.x + point.x),
                "cy": @core.any(state.y + point.y),
                "r": @core.any(5.0 * scale),
                "fill": @core.any("#a8a6ff"),
                "className": @core.any("bezier-handle"),
              },
              [],
            ),
          )
        }
      }
      result.push(
        h(
          "g",
          {
            "transform": stage_rotation(stored),
            "stroke": @core.any("#9292e7"),
            "strokeWidth": @core.any(scale),
          },
          nodes,
        ),
      )
    }
  }
  result
}

///|
fn stage_overlay(
  controller : StageController,
  selection : Array[@core.Any],
  hovered : @core.Any?,
  marquee : @geometry.Rectangle?,
) -> @react.Element {
  let nodes : Array[&@react.ReactNode] = []
  let scale = controller.scale
  if hovered is Some(item) {
    let id : String = item._get("object")._get("id").cast()
    if !controller.selected.iter().any(fn(value) { value == id }) {
      let b = stage_bounds(controller.renderer._call("objectBounds", [item]))
      nodes.push(
        h(
          "rect",
          {
            "data-hover-id": @core.any(id),
            "transform": stage_rotation(item._get("state")),
            "x": @core.any(b.x),
            "y": @core.any(b.y),
            "width": @core.any(b.width.max(1.0)),
            "height": @core.any(b.height.max(1.0)),
            "fill": @core.any("none"),
            "stroke": @core.any(
              if stage_object_locked(controller.scene, id) {
                "#aaa6b9"
              } else {
                "#9696eb"
              },
            ),
            "strokeOpacity": @core.any("0.7"),
            "strokeWidth": @core.any(scale),
            "strokeDasharray": @core.any("\{4.0 * scale} \{3.0 * scale}"),
          },
          [],
        ),
      )
    }
  }
  if controller.can_edit {
    for item in selection {
      nodes.push(stage_selection(controller, item))
    }
  }
  for item in stage_paths(controller) {
    nodes.push(item)
  }
  if marquee is Some(area) {
    nodes.push(
      h(
        "rect",
        {
          "data-testid": @core.any("selection-marquee"),
          "x": @core.any(area.x),
          "y": @core.any(area.y),
          "width": @core.any(area.width),
          "height": @core.any(area.height),
          "fill": @core.any("#9696eb"),
          "fillOpacity": @core.any("0.12"),
          "stroke": @core.any("#9696eb"),
          "strokeWidth": @core.any(scale),
        },
        [],
      ),
    )
  }
  for item in stage_peers(controller) {
    nodes.push(item)
  }
  h(
    "svg",
    {
      "className": @core.any("stage-overlay"),
      "viewBox": @core.any("0 0 \{controller.width} \{controller.height}"),
      "aria-hidden": @core.any("true"),
    },
    nodes,
  )
}
