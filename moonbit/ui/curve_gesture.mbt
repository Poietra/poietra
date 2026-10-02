///|
priv struct CurveGesture {
  pointer : Int
  point : @editor.CurvePoint
  before : UndoEntry?
  element : @core.Any
  mut last : @scene.Easing
  mut undo : UndoEntry?
  mut moved : Bool
}

///|
priv struct CurveController {
  history : GestureHistory
  notify : (String) -> Unit
  latest : @react.ReactRef[EasingView]
  plot : @react.ReactRef[@core.Any]
  gesture : @react.ReactRef[CurveGesture]
  ignore_click : @react.ReactRef[Bool]
}

///|
fn CurveController::current(self : CurveController) -> @scene.Easing? {
  let latest = self.latest.get_current().unwrap()
  match latest.current {
    Some(read) => read()
    None => latest.value
  }
}

///|
fn CurveController::disabled(self : CurveController) -> Bool {
  self.latest.get_current().unwrap().disabled
}

///|
fn CurveController::finish(self : CurveController, cancel : Bool) -> Unit {
  guard self.gesture.get_current() is Some(current) else { return }
  self.gesture.set_current(None)
  @core.throwable(fn() {
    if cancel &&
      current.undo is Some(entry) &&
      current.undo != current.before &&
      self.history.top() == current.undo {
      self.history.rollback(entry)
    }
  }) catch {
    failure =>
      (self.notify)(
        error_message(
          ui_native_error(failure),
          "ドラッグを取り消せませんでした。",
        ),
      )
  }
  self.history.end()
  self.ignore_click.set_current(Some(current.moved))
  @core.throwable(fn() {
    if current.element
      ._call("hasPointerCapture", [@core.any(current.pointer)])
      .cast() {
      current.element._call("releasePointerCapture", [
        @core.any(current.pointer),
      ])
      |> ignore
    }
  }) catch {
    _ => ()
  }
}

///|
fn CurveController::down(
  self : CurveController,
  event : @core.Any,
  point : @editor.CurvePoint,
) -> Unit {
  let button : Int = event._get("button").cast()
  if button != 0 || self.disabled() || self.gesture.get_current() is Some(_) {
    return
  }
  let element = event._get("currentTarget")
  element._call("focus", [
    @core.from_entries([("preventScroll", @core.any(true))]),
  ])
  |> ignore
  guard self.current() is Some(current) &&
    current is CubicBezier(_, _, _, _) &&
    self.plot.get_current() is Some(_) else {
    return
  }
  self.ignore_click.set_current(Some(false))
  let gesture : CurveGesture = {
    pointer: event._get("pointerId").cast(),
    point,
    last: current,
    before: self.history.top(),
    element,
    undo: None,
    moved: false,
  }
  self.gesture.set_current(Some(gesture))
  self.history.begin()
  try
    @core.throwable(fn() {
      element._call("setPointerCapture", [@core.any(gesture.pointer)])
    })
    |> ignore
  catch {
    _ => {
      self.finish(true)
      return
    }
  }
  prevent_default(event)
}

///|
fn CurveController::pointer_move(
  self : CurveController,
  event : @core.Any,
) -> Unit {
  guard self.gesture.get_current() is Some(current) &&
    self.plot.get_current() is Some(plot) else {
    return
  }
  let pointer : Int = event._get("pointerId").cast()
  if current.pointer != pointer {
    return
  }
  let live = self.current()
  if self.disabled() ||
    live != Some(current.last) ||
    !(live is Some(CubicBezier(_, _, _, _))) {
    self.finish(true)
    return
  }
  if current.undo is Some(_) && self.history.top() != current.undo {
    self.finish(false)
    return
  }
  let rect = plot._call("getBoundingClientRect", [])
  let width : Double = rect._get("width").cast()
  let height : Double = rect._get("height").cast()
  if width <= 0.0 || height <= 0.0 {
    self.finish(true)
    return
  }
  let client_x : Double = event._get("clientX").cast()
  let client_y : Double = event._get("clientY").cast()
  let left : Double = rect._get("left").cast()
  let top : Double = rect._get("top").cast()
  let next = @editor.move_curve_point(
    current.last,
    current.point,
    (client_x - left) / width,
    1.0 - (client_y - top) / height,
  )
  if live == Some(next) {
    return
  }
  @core.throwable(fn() {
    (self.latest.get_current().unwrap().on_change)(next, false)
    current.last = next
    current.undo = self.history.top()
    current.moved = true
  }) catch {
    _ => self.finish(true)
  }
}

///|
fn CurveController::end(
  self : CurveController,
  event : @core.Any,
  cancel : Bool,
) -> Unit {
  if self.gesture.get_current() is Some(current) {
    let pointer : Int = event._get("pointerId").cast()
    if current.pointer == pointer {
      self.finish(cancel)
    }
  }
}

///|
fn CurveController::coordinate(
  self : CurveController,
  coordinate : @editor.CurveCoordinate,
  value : Double,
) -> Unit {
  if !self.disabled() &&
    self.current() is Some(CubicBezier(_, _, _, _) as current) {
    (self.latest.get_current().unwrap().on_change)(
      @editor.edit_curve_coordinate(current, coordinate, value),
      true,
    )
  }
}
