///|
fn StageController::down(self : StageController, event : @core.Any) -> Unit {
  if !self.can_edit ||
    event._get("button").cast() != 0 ||
    self.gesture.get_current() is Some(_) {
    return
  }
  let element = event._get("currentTarget")
  element._call("focus", [host_record({ "preventScroll": @core.any(true) })])
  |> ignore
  let scene = self.store._call("scene", [@core.any(self.scene_id)])
  guard self.point(event) is Some(start) else { return }
  let target = event._get("target")
  let make = fn(mode : StageMode) {
    StageGesture::{
      pointer: event._get("pointerId").cast(),
      scene_id: self.scene_id,
      composition_id: self.composition_id,
      start,
      mode,
      element,
      undo_before: top_undo(self.store),
      undo: @core.undefined(),
      changed: false,
      feedback: None,
    }
  }
  (self.hover)(None)
  (self.report)(@core.null())
  let selected = if self.selected.length() == 1 {
    Some(self.selected[0])
  } else {
    None
  }
  let handle = stage_handle(target, "data-path-handle")
  let transform = match stage_handle(target, "data-transform-handle") {
    Some(name) => @editor.stage_transform(name)
    None => None
  }
  let mode = if handle is Some(handle) && selected is Some(id) {
    let object = scene._get("objects")._get(id)
    let selection = self.editor._get("selection")
    let transition = if selection._get("kind").cast() == "transition" {
      Some(string_value(selection._get("id")))
    } else {
      None
    }
    if !truthy(object) ||
      truthy(object._get("locked")) ||
      (transition is None && !self.state_editing) {
      return
    }
    EditPath(
      id,
      if handle == "c1" {
        @editor.First
      } else {
        @editor.Second
      },
      transition,
    )
  } else if transform is Some(transform) && selected is Some(id) {
    let object = scene._get("objects")._get(id)
    if !self.state_editing || !truthy(object) || truthy(object._get("locked")) {
      return
    }
    let stored = @boundary.state_for(scene, self.composition_id, id)
    if !truthy(stored) || !truthy(stored._get("visible")) {
      return
    }
    let state = @boundary.read_object_state(stored)
    let bounds = stage_bounds(
      self.renderer._call("objectBounds", [
        host_record({
          "object": object,
          "state": stored,
          "writeProgress": @core.any(1),
          "order": @core.any("together"),
        }),
      ]),
    )
    let stroke = state.strokeWidth.max(0.0)
    TransformObject(
      id,
      transform,
      state,
      bounds.width - stroke,
      bounds.height - stroke,
    )
  } else if self.tool is DrawTool(kind) {
    if !self.state_editing {
      return
    }
    (self.draw)(
      Some({
        ..@scene.default_state(kind),
        x: start.x,
        y: start.y,
        width: 1.0,
        height: 1.0,
      }),
    )
    DrawObject(kind)
  } else {
    let id = self.hit(start, target)
    let object = id
      .map(fn(id) { scene._get("objects")._get(id) })
      .unwrap_or(@core.undefined())
    let additive = truthy(event._get("shiftKey"))
    if !truthy(object) || id is None {
      let area : StageMarquee = {
        initial: self.selected.iter().to_array(),
        additive,
        active: false,
      }
      if !additive {
        self.select([])
      }
      self.capture(event, make(SelectArea(area)))
      return
    }
    let id = id.unwrap()
    let ids = if additive {
      @editor.select_layer_members(self.selected.iter().to_array(), [id], true)
    } else if self.selected.iter().any(fn(value) { value == id }) {
      self.selected.iter().to_array()
    } else {
      [id]
    }
    self.select(host_array(ids))
    if !self.state_editing || truthy(object._get("locked")) || !ids.contains(id) {
      return
    }
    let linked : FixedArray[String] = self.store
      ._call("linkedIds", [@core.any(self.scene_id), @core.any(host_array(ids))])
      .cast()
    let positions : Map[String, @scene.Point] = Map([])
    for id in linked {
      let state = @boundary.state_for(scene, self.composition_id, id)
      if truthy(state) && truthy(state._get("visible")) {
        positions[id] = {
          x: state._get("x").cast(),
          y: state._get("y").cast(),
        }
      }
    }
    MoveObjects(positions)
  }
  self.capture(event, make(mode))
}

///|
extern "js" fn pointer_distance(x : Double, y : Double) -> Double = "Math.hypot"

///|
fn StageController::up(self : StageController, event : @core.Any) -> Unit {
  guard self.gesture.get_current() is Some(current) else { return }
  if current.pointer != event._get("pointerId").cast() {
    return
  }
  if current.mode is DrawObject(kind) {
    guard self.point(event) is Some(at) else {
      self.finish(true)
      return
    }
    let click = pointer_distance(at.x - current.start.x, at.y - current.start.y) <
      8.0
    let state = if click {
      let state = {
        ..@scene.default_state(kind),
        x: current.start.x,
        y: current.start.y,
      }
      if kind is Text || kind is Equation {
        { ..state, width: 320.0, height: 80.0, }
      } else {
        state
      }
    } else {
      @editor.stage_drawing(
        kind,
        current.start,
        at,
        truthy(event._get("shiftKey")),
      )
    }
    let id : String = self.store
      ._call("addObject", [
        @core.any(current.scene_id),
        @core.any(current.composition_id),
        @core.any(@scene.object_kind_name(kind)),
        @boundary.write_object_state(state),
      ])
      .cast()
    self.finish(false)
    self.select([id])
    self.editor._get("setTool")._invoke([@core.any("select")]) |> ignore
    if kind is Text || kind is Equation {
      self.editor
      ._get("requestTextEdit")
      ._invoke([@core.any(id), @core.any(current.composition_id)])
      |> ignore
    }
  } else {
    self.finish(false)
  }
}
