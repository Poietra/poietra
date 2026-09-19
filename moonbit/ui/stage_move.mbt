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
      let object = self.scene._get("objects")._get(id)
      if truthy(object) && truthy(object._get("locked")) {
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
    self.store._call("presence", [
      host_record({
        "sceneId": @core.any(self.scene_id),
        "compositionId": @core.any(self.composition_id),
        "cursor": stage_point(at),
      }),
    ])
    |> ignore
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
      let objects : FixedArray[@core.Any] = self.frame._get("objects").cast()
      for item in objects {
        let state = item._get("state")
        let id : String = item._get("object")._get("id").cast()
        let opacity : Double = state._get("opacity").cast()
        let progress : Double = item._get("writeProgress").cast()
        if truthy(self.scene._get("objects")._get(id)) &&
          truthy(state._get("visible")) &&
          opacity > 0.0 &&
          progress > 0.0 &&
          @geometry.rectangle_contains_bounds(
            rectangle,
            stage_bounds(self.renderer._call("objectBounds", [item])),
            stage_placement(state),
          ) &&
          !enclosed.contains(id) {
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
      (self.report)(encode_status(Some(status)))
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
  let scene = self.store._call("scene", [@core.any(current.scene_id)])
  let object_id = match current.mode {
    EditPath(id, _, _) | TransformObject(id, _, _, _, _) => Some(id)
    _ => None
  }
  let object = object_id
    .map(fn(id) { scene._get("objects")._get(id) })
    .unwrap_or(@core.undefined())
  if object_id is Some(_) && (!truthy(object) || truthy(object._get("locked"))) {
    self.finish(true)
    return
  }
  current.changed = current.changed ||
    pointer_distance(at.x - current.start.x, at.y - current.start.y) >
    self.scale
  match current.mode {
    EditPath(id, handle, transition_id) => {
      let key = if handle is First { "c1" } else { "c2" }
      match transition_id {
        Some(transition_id) => {
          let transition = scene._get("transitions")._get(transition_id)
          let track = if truthy(transition) {
            transition._get("tracks")._get(id)
          } else {
            @core.undefined()
          }
          if truthy(track) && truthy(track._get("path")) {
            let path = ui_shallow_copy(track._get("path"))
            path._set(key, stage_point(at))
            self.store._call("setTrack", [
              @core.any(current.scene_id),
              @core.any(transition_id),
              @core.any(id),
              host_record({ "path": path }),
              @core.any(false),
            ])
            |> ignore
          }
        }
        None => {
          let state = @boundary.state_for(scene, current.composition_id, id)
          if truthy(state) {
            let path = ui_shallow_copy(state._get("path"))
            path._set(
              key,
              stage_point(@geometry.world_to_local(at, stage_placement(state))),
            )
            self.store._call("updateState", [
              @core.any(current.scene_id),
              @core.any(current.composition_id),
              @core.any(id),
              host_record({ "path": path }),
              @core.any(false),
            ])
            |> ignore
          }
        }
      }
      self.feedback(current, at, None)
    }
    TransformObject(id, transform, state, width, height) => {
      let kind = @boundary.read_object_kind(object._get("kind"))
      let patch = if transform is RotateObject {
        host_record({
          "rotation": @core.any(
            @geometry.rotation_from_pointer(
              { x: state.x, y: state.y, rotation: state.rotation, },
              current.start,
              at,
              shift,
            ),
          ),
        })
      } else {
        let changed = @geometry.resize_from_corner(
          state,
          width,
          height,
          @editor.stage_transform_name(transform),
          { x: at.x - current.start.x, y: at.y - current.start.y, },
          if kind is Image || kind is Video {
            !shift
          } else {
            shift
          },
          kind is Text || kind is Equation,
        )
        let patch = host_record({
          "x": @core.any(changed.x),
          "y": @core.any(changed.y),
          "width": @core.any(changed.width),
          "height": @core.any(changed.height),
        })
        if changed.font_size is Some(size) {
          patch._set("fontSize", @core.any(size))
        }
        patch
      }
      self.store._call("updateState", [
        @core.any(current.scene_id),
        @core.any(current.composition_id),
        @core.any(id),
        patch,
        @core.any(false),
      ])
      |> ignore
      self.feedback(current, at, Some(patch))
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
      let targets = @core.new_object()
      for id, position in positions {
        let object = scene._get("objects")._get(id)
        if !truthy(object) || !truthy(object._get("locked")) {
          targets._set(id, stage_point(position))
        }
      }
      self.store._call("translate", [
        @core.any(current.scene_id),
        @core.any(current.composition_id),
        targets,
        @core.any(dx),
        @core.any(dy),
      ])
      |> ignore
      self.feedback(
        current,
        { x: current.start.x + dx, y: current.start.y + dy, },
        None,
      )
    }
    _ => ()
  }
  current.undo = top_undo(self.store)
}
