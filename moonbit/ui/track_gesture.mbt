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
  undo_before : @core.Any
  mut undo : @core.Any
  element : @core.Any
}

///|
priv struct TrackController {
  store : @core.Any
  scene_id : String
  transition_id : String
  object_id : String
  object_name : String
  label : String
  channel : @scene.PropertyChannel?
  lane : @react.ReactRef[@core.Any]
  drag : @react.ReactRef[TrackGesture]
  report : (@core.Any) -> Unit
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
    host_record({
      "kind": @core.any("active"),
      "label": @core.any(label),
      "detail": @core.any(
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
      truthy(current.undo) &&
      !@core.equal(current.undo, current.undo_before) &&
      @core.equal(top_undo(self.store), current.undo) {
      // The exact owned item may now contain only peer-protected fields. Never
      // fall through to an earlier action when that item has nothing left to undo.
      self.store._call("rollbackGesture", [current.undo]) |> ignore
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
  ui_quiet(self.store, "endGesture")
  (self.report)(
    if truthy(current.undo) {
      host_record({
        "kind": @core.any(if cancel { "cancelled" } else { "complete" }),
        "label": @core.any(
          if cancel {
            "時間の調整をキャンセル"
          } else {
            "時間を確定"
          },
        ),
        "detail": if cancel {
          @core.undefined()
        } else {
          @core.any(track_detail(current.last_start, current.last_duration))
        },
      })
    } else {
      @core.null()
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
fn TrackController::timing(
  self : TrackController,
  track : @core.Any,
) -> @scene.Timing {
  match self.channel {
    None => @boundary.read_timing(track)
    Some(channel) =>
      @boundary.read_timing(
        @boundary.get_property_timing(
          track,
          @editor.property_channel_name(channel),
        ),
      )
  }
}

///|
fn TrackController::materialized(
  self : TrackController,
  animation : @core.Any,
) -> Bool {
  match self.channel {
    None => truthy(animation._get("existing"))
    Some(channel) =>
      @boundary.has_property_timing(
        animation._get("track"),
        @editor.property_channel_name(channel),
      )
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
  (self.select)([self.object_id])
  let width : Double = self.lane
    .get_current()
    .map(fn(lane) {
      lane._call("getBoundingClientRect", [])._get("width").cast()
    })
    .unwrap_or(0.0)
  let scene = self.store._call("scene", [@core.any(self.scene_id)])
  let transition = scene._get("transitions")._get(self.transition_id)
  if !truthy(transition) {
    return
  }
  let current = @boundary.visible_animation(scene, transition, self.object_id)
  let total : Double = transition._get("duration").cast()
  if !truthy(current) ||
    truthy(current._get("object")._get("locked")) ||
    self.playing ||
    total <= 0.0 ||
    width <= 0.0 {
    return
  }
  if self.channel is Some(_) && !self.materialized(current) {
    return
  }
  let timing = self.timing(current._get("track"))
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
    materialized: self.materialized(current),
    undo_before: top_undo(self.store),
    undo: @core.undefined(),
    element,
  }
  self.drag.set_current(Some(gesture))
  self.store._call("beginGesture", []) |> ignore
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
  let scene = self.store._call("project", [])._get("scenes")._get(self.scene_id)
  let transition = if truthy(scene) {
    scene._get("transitions")._get(self.transition_id)
  } else {
    @core.undefined()
  }
  let current = if truthy(transition) {
    @boundary.visible_animation(scene, transition, self.object_id)
  } else {
    @core.undefined()
  }
  if !truthy(current) ||
    truthy(current._get("object")._get("locked")) ||
    (initial.materialized && !self.materialized(current)) ||
    transition._get("duration").cast() != initial.total {
    self.finish(true)
    return
  }
  let timing = self.timing(current._get("track"))
  if timing.start != initial.last_start ||
    timing.duration != initial.last_duration {
    self.finish(true)
    return
  }
  if truthy(initial.undo) && !@core.equal(top_undo(self.store), initial.undo) {
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
        self.store._call("setPropertyTiming", [
          @core.any(self.scene_id),
          @core.any(self.transition_id),
          @core.any(self.object_id),
          @core.any(@editor.property_channel_name(channel)),
          @boundary.write_timing({ start, duration, easing: timing.easing, }),
          @core.any(false),
        ])
        |> ignore
      None => {
        let patch = @core.new_object()
        if start != timing.start {
          patch._set("start", @core.any(start))
        }
        if duration != timing.duration {
          patch._set("duration", @core.any(duration))
        }
        self.store._call("setTrack", [
          @core.any(self.scene_id),
          @core.any(self.transition_id),
          @core.any(self.object_id),
          patch,
          @core.any(false),
        ])
        |> ignore
      }
    }
    initial.last_start = start
    initial.last_duration = duration
    initial.materialized = true
    initial.undo = top_undo(self.store)
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
