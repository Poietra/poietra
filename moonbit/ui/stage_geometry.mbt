///|
fn stage_geometry_handles(
  controller : StageController,
) -> Array[&@react.ReactNode] {
  let nodes : Array[&@react.ReactNode] = []
  guard controller.can_edit &&
    controller.state_editing &&
    controller.tool is SelectTool &&
    controller.selected.length() == 1 else {
    return nodes
  }
  let id = controller.selected[0]
  guard controller.frame_item(id) is Some(item) else { return nodes }
  let object = item._get("object")
  let kind = @boundary.read_object_kind(object._get("kind"))
  guard (kind == @scene.Geometry || kind == @scene.Network) &&
    !stage_object_locked(controller.scene, id) else {
    return nodes
  }
  let state = @boundary.read_object_state(item._get("state"))
  guard state.visible && state.opacity > 0.0 else { return nodes }
  let points : Map[String, @scene.GeometryPoint] = if kind == @scene.Network {
    let points : Map[String, @scene.GeometryPoint] = Map([])
    for id, p in state.network.unwrap_or(@scene.default_network()).nodes {
      points[id] = {
        kind: @scene.FreePoint,
        x: p.x,
        y: p.y,
        label: p.label,
        deleted: p.deleted,
        from: None,
        to: None,
      }
    }
    points
  } else {
    state.geometry.unwrap_or(@scene.default_geometry()).points
  }
  let progress : Double = item._get("writeProgress").cast()
  let unit = @scene.geometry_unit(state)
  if progress <= 0.0 || unit <= 1.0e-9 {
    return nodes
  }
  let world = stage_item_matrix(item)
  let ids = points.keys().to_array()
  ids.sort()
  for point_id in ids {
    let point = points[point_id]
    if point.kind != @scene.FreePoint || point.deleted == Some(true) {
      continue
    }
    let at = world.point({ x: point.x * unit, y: -point.y * unit, })
    if !stage_graph_point_visible(item, at) {
      continue
    }
    nodes.push(
      h(
        "g",
        {
          "key": @core.any(point_id),
          "data-geometry-handle": @core.any(point_id),
          "style": host_record({
            "pointerEvents": @core.any("all"),
            "cursor": @core.any("grab"),
          }),
        },
        [
          h(
            "circle",
            {
              "cx": @core.any(at.x),
              "cy": @core.any(at.y),
              "r": @core.any(9.0 * controller.scale),
              "fill": @core.any("transparent"),
            },
            [],
          ),
          h(
            "circle",
            {
              "cx": @core.any(at.x),
              "cy": @core.any(at.y),
              "r": @core.any(4.0 * controller.scale),
              "fill": @core.any("#181820"),
              "stroke": @core.any("#a9a7fb"),
              "strokeWidth": @core.any(1.5 * controller.scale),
            },
            [],
          ),
        ],
      ),
    )
  }
  nodes
}
