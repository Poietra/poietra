///|
fn StageController::pointer_move(
  self : StageController,
  event : @core.Any,
) -> Unit {
  guard self.point(event) is Some(at) else { return }
  if self.gesture.get_current() is None &&
    self.surface.get_current() is Some(surface) {
    let target = event._get("target")
    let id = if self.tool is SelectTool && self.can_edit {
      self.hit(at, target)
    } else {
      None
    }
    (self.hover)(id)
    let handle = truthy(
      target._call("closest", [
        @core.any("[data-transform-handle], [data-path-handle]"),
      ]),
    )
    let cursor = if handle {
      ""
    } else if id is Some(id) {
      if stage_object_locked(self.scene, id) {
        "not-allowed"
      } else if self.state_editing {
        "move"
      } else {
        "default"
      }
    } else {
      ""
    }
    surface._get("style")._set("cursor", @core.any(cursor))
  }
  let now : Double = @core.global_this()
    ._get("performance")
    ._call("now", [])
    .cast()
  if now - self.cursor_time.get_current().unwrap_or(0.0) > 40.0 {
    self.cursor_time.set_current(Some(now))
    self.binding.presence(Some(at))
  }
  guard self.gesture.get_current() is Some(current) else { return }
  if current.pointer != event._get("pointerId").cast() {
    return
  }
  let shift = truthy(event._get("shiftKey"))
  match current.mode {
    SelectArea(area) => {
      if !area.active &&
        pointer_distance(at.x - current.start.x, at.y - current.start.y) <
        4.0 * self.scale {
        return
      }
      area.active = true
      current.changed = true
      let rectangle = @geometry.rectangle_from_points(current.start, at)
      (self.marquee)(Some(rectangle))
      let enclosed : Array[String] = if area.additive {
        area.initial.copy()
      } else {
        []
      }
      for id in self.enclosed(rectangle) {
        if !enclosed.contains(id) {
          enclosed.push(id)
        }
      }
      self.select(host_array(enclosed))
      let status : @editor.OperationStatus = {
        kind: @editor.Active,
        label: if area.additive {
          "選択に追加"
        } else {
          "範囲を選択"
        },
        detail: Some("\{enclosed.length()} 個 · Esc で戻す"),
      }
      current.feedback = Some(status)
      (self.report)(Some(status))
      return
    }
    DrawObject(kind) => {
      let state = @editor.stage_drawing(kind, current.start, at, shift)
      (self.draw)(Some(state))
      self.feedback(
        current,
        { x: current.start.x + state.width, y: current.start.y + state.height, },
        None,
      )
      return
    }
    _ => ()
  }
  let binding = current.binding
  guard binding.current() is Some(snapshot) else {
    self.finish(true)
    return
  }
  let object_id = match current.mode {
    EditPath(id, _, _) | TransformObject(id, _, _, _, _) => Some(id)
    _ => None
  }
  let object = match object_id {
    Some(id) => snapshot.object(id)
    None => None
  }
  if object_id is Some(_) && (object is None || object.unwrap().locked) {
    self.finish(true)
    return
  }
  current.changed = current.changed ||
    pointer_distance(at.x - current.start.x, at.y - current.start.y) >
    self.scale
  match current.mode {
    EditPath(id, handle, transition_id) => {
      if snapshot.has_path(id, transition_id) {
        let matrix = match transition_id {
          Some(_) => self.path_parent(id)
          None => snapshot.object_matrix(id)
        }
        guard matrix.inverse() is Some(inverse) else { return }
        binding.set_path_point(id, transition_id, handle, inverse.point(at))
      }
      self.feedback(current, at, None)
    }
    TransformObject(id, transform, state, width, height) => {
      guard snapshot.parent_matrix(id).inverse() is Some(inverse) else {
        return
      }
      let start_local = inverse.point(current.start)
      let at_local = inverse.point(at)
      let kind = object.unwrap().kind
      let value : StageTransformValue = if transform is RotateObject {
        Rotation(
          @geometry.rotation_from_pointer(
            { x: state.x, y: state.y, rotation: state.rotation, },
            start_local,
            at_local,
            shift,
          ),
        )
      } else {
        let changed = @geometry.resize_from_corner(
          state,
          width,
          height,
          @editor.stage_transform_name(transform),
          { x: at_local.x - start_local.x, y: at_local.y - start_local.y, },
          if kind is Image || kind is Video {
            !shift
          } else {
            shift
          },
          kind is Text || kind is Equation,
        )
        Size(changed)
      }
      binding.set_transform(id, value)
      self.feedback(current, at, Some(value))
    }
    MoveObjects(positions) => {
      let mut dx = at.x - current.start.x
      let mut dy = at.y - current.start.y
      if shift {
        if dx.abs() > dy.abs() {
          dy = 0.0
        } else {
          dx = 0.0
        }
      }
      let targets : Map[String, @scene.Point] = Map([])
      for id, position in positions {
        if snapshot.object(id) is Some(object) && !object.locked {
          targets[id] = position
        }
      }
      binding.translate(targets, { x: dx, y: dy, })
      self.feedback(
        current,
        { x: current.start.x + dx, y: current.start.y + dy, },
        None,
      )
    }
    _ => ()
  }
  current.undo = binding.history().top()
}
