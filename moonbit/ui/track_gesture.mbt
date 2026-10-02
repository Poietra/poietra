///|
priv struct TrackGesture {
  pointer : Int
  x : Double
  start : Double
  duration : Double
  total : Double
  width : Double
  edge : @editor.TimingEdge
  mut last_start : Double
  mut last_duration : Double
  mut materialized : Bool
  undo_before : UndoEntry?
  mut undo : UndoEntry?
  element : @core.Any
}

///|
priv struct TrackController {
  binding : AnimationBinding
  history : GestureHistory
  object_name : String
  label : String
  channel : @scene.PropertyChannel?
  lane : @react.ReactRef[@core.Any]
  drag : @react.ReactRef[TrackGesture]
  report : (@editor.OperationStatus?) -> Unit
  select : (FixedArray[String]) -> Unit
  notify : (String) -> Unit
  playing : Bool
}

///|
fn track_detail(start : Double, duration : Double) -> String {
  @boundary.format_milliseconds(start) +
  "–" +
  @boundary.format_milliseconds(start + duration) +
  " ms"
}

///|
fn TrackController::feedback(
  self : TrackController,
  gesture : TrackGesture,
  changed : Bool,
) -> Unit {
  let action = match gesture.edge {
    TrimStart => "開始を調整"
    TrimEnd => "終了を調整"
    MoveTiming => "時間を移動"
  }
  let label = self.object_name +
    (if self.channel is Some(_) { " · " + self.label } else { "" }) +
    " · " +
    action
  (self.report)(
    Some({
      kind: Active,
      label,
      detail: Some(
        track_detail(gesture.last_start, gesture.last_duration) +
        (if changed { " · Esc で戻す" } else { "" }),
      ),
    }),
  )
}

///|
fn TrackController::finish(self : TrackController, cancel : Bool) -> Unit {
  guard self.drag.get_current() is Some(current) else { return }
  self.drag.set_current(None)
  @core.throwable(fn() {
    if cancel &&
      current.undo is Some(entry) &&
      current.undo != current.undo_before &&
      self.history.top() == current.undo {
      // The exact owned item may now contain only peer-protected fields. Never
      // fall through to an earlier action when that item has nothing left to undo.
      self.history.rollback(entry)
    }
  }) catch {
    failure =>
      (self.notify)(
        error_message(
          ui_native_error(failure),
          "時間の調整を取り消せませんでした。",
        ),
      )
  }
  self.history.end()
  (self.report)(
    if current.undo is Some(_) {
      Some({
        kind: if cancel {
          Cancelled
        } else {
          Complete
        },
        label: if cancel {
          "時間の調整をキャンセル"
        } else {
          "時間を確定"
        },
        detail: if cancel {
          None
        } else {
          Some(track_detail(current.last_start, current.last_duration))
        },
      })
    } else {
      None
    },
  )
  @core.throwable(fn() {
    if truthy(
        current.element._call("hasPointerCapture", [@core.any(current.pointer)]),
      ) {
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
fn TrackController::down(self : TrackController, event : @core.Any) -> Unit {
  if event._get("button").cast() != 0 || self.drag.get_current() is Some(_) {
    return
  }
  let element = event._get("currentTarget")
  element._call("focus", [host_record({ "preventScroll": @core.any(true) })])
  |> ignore
  (self.select)([self.binding.target.object_id])
  let width : Double = self.lane
    .get_current()
    .map(fn(lane) {
      lane._call("getBoundingClientRect", [])._get("width").cast()
    })
    .unwrap_or(0.0)
  guard self.binding.timing(self.channel) is Some(current) else { return }
  let total = current.limit
  if current.locked || self.playing || total <= 0.0 || width <= 0.0 {
    return
  }
  if self.channel is Some(_) && !current.materialized {
    return
  }
  let timing = current.timing
  let gesture : TrackGesture = {
    pointer: event._get("pointerId").cast(),
    x: event._get("clientX").cast(),
    start: @scene.clamp(timing.start, 0.0, total),
    duration: @scene.clamp(
      timing.duration,
      0.0,
      (total - timing.start).max(0.0),
    ),
    total,
    width,
    edge: pointer_edge(event),
    last_start: timing.start,
    last_duration: timing.duration,
    materialized: current.materialized,
    undo_before: self.history.top(),
    undo: None,
    element,
  }
  self.drag.set_current(Some(gesture))
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
  self.feedback(gesture, false)
}

///|
fn TrackController::pointer_move(
  self : TrackController,
  event : @core.Any,
) -> Unit {
  guard self.drag.get_current() is Some(initial) else { return }
  if initial.pointer != event._get("pointerId").cast() {
    return
  }
  guard self.binding.timing(self.channel) is Some(current) else {
    self.finish(true)
    return
  }
  if current.locked ||
    (initial.materialized && !current.materialized) ||
    current.limit != initial.total {
    self.finish(true)
    return
  }
  let timing = current.timing
  if timing.start != initial.last_start ||
    timing.duration != initial.last_duration {
    self.finish(true)
    return
  }
  if initial.undo is Some(_) && self.history.top() != initial.undo {
    self.finish(false)
    return
  }
  let x : Double = event._get("clientX").cast()
  let delta = round_number(
      (x - initial.x) / initial.width * initial.total / 10.0,
    ) *
    10.0
  let (start, duration) = @editor.animation_gesture(
    initial.start,
    initial.duration,
    initial.total,
    initial.edge,
    delta,
  )
  if start == timing.start && duration == timing.duration {
    return
  }
  @core.throwable(fn() {
    match self.channel {
      Some(channel) =>
        self.binding.set_timing(
          channel,
          Some({ start, duration, easing: timing.easing, }),
          false,
        )
      None => self.binding.set_track_range(timing, { start, duration, }, false)
    }
    initial.last_start = start
    initial.last_duration = duration
    initial.materialized = true
    initial.undo = self.history.top()
    self.feedback(initial, true)
  }) catch {
    _ => self.finish(true)
  }
}

///|
fn TrackController::end(
  self : TrackController,
  event : @core.Any,
  cancel : Bool,
) -> Unit {
  if self.drag.get_current() is Some(current) &&
    current.pointer == event._get("pointerId").cast() {
    self.finish(cancel)
  }
}
