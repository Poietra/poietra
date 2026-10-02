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
  guard self.binding.current() is Some(snapshot) else { return }
  guard self.point(event) is Some(start) else { return }
  let target = event._get("target")
  let make = fn(mode : StageMode) {
    StageGesture::{
      pointer: event._get("pointerId").cast(),
      binding: self.binding,
      start,
      mode,
      element,
      undo_before: self.binding.history().top(),
      undo: None,
      changed: false,
      feedback: None,
    }
  }
  (self.hover)(None)
  (self.report)(None)
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
    let object = snapshot.object(id)
    let selection = self.editor.selection
    let transition = if selection is TransitionSelection(_) {
      Some(selection.id())
    } else {
      None
    }
    if object is None ||
      object.unwrap().locked ||
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
    guard self.state_editing &&
      snapshot.object(id) is Some(object) &&
      !object.locked &&
      self.binding.transform_start(snapshot, id) is Some((state, width, height)) else {
      return
    }
    TransformObject(id, transform, state, width, height)
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
    let object = match id {
      Some(id) => snapshot.object(id)
      None => None
    }
    let additive = truthy(event._get("shiftKey"))
    if object is None || id is None {
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
    if !self.state_editing || object.unwrap().locked || !ids.contains(id) {
      return
    }
    let positions = snapshot.positions(self.binding.linked_ids(ids))
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
    guard current.binding.current() is Some(_) && self.point(event) is Some(at) else {
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
    let id = current.binding.add_object(kind, state)
    self.finish(false)
    self.select([id])
    (self.editor.actions.set_tool)(@editor.SelectTool)
    if kind is Text || kind is Equation {
      (self.editor.actions.request_text_edit)(
        id,
        current.binding.composition_id,
      )
    }
  } else {
    self.finish(false)
  }
}
