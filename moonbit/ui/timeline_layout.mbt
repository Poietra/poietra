///|
priv struct TimelineResize {
  pointer : Int
  y : Double
  height : Double
  requested : Double?
  element : @core.Any
}

///|
priv struct TimelineLayout {
  element : @react.ReactRef[@core.Any]
  height : Double
  handle : @react.Element
}

///|
// Panel size belongs to this browser, never to the shared document or editing Undo.
fn use_timeline_layout() -> TimelineLayout {
  let element = @react.use_ref((None : @core.Any?))
  let drag = @react.use_ref((None : TimelineResize?))
  let (requested, set_requested) = @react.use_state((None : Double?))
  let (available, set_available) = @react.use_state(800.0)
  // Leave room for the fixed cards/transport and a usable scrolling track lane.
  let minimum = 280.0
  let maximum = (available - 200.0).max(minimum)
  let height = @scene.clamp(
    requested.unwrap_or((available * 0.42).min(380.0)),
    minimum,
    maximum,
  )
  let finish = fn(cancel : Bool) {
    if drag.get_current() is Some(current) {
      drag.set_current(None)
      if cancel {
        set_requested(current.requested)
      }
      if truthy(
          current.element._call("hasPointerCapture", [
            @core.any(current.pointer),
          ]),
        ) {
        current.element._call("releasePointerCapture", [
          @core.any(current.pointer),
        ])
        |> ignore
      }
    }
  }
  @react.use_effect(
    fn() {
      guard element.get_current() is Some(panel) else { return fn() { () } }
      let parent = panel._get("parentElement")
      let observer = @core.new(@core.global_this()._get("ResizeObserver"), [
        @core.any(fn(entries : FixedArray[@core.Any]) {
          set_available(entries[0]._get("contentRect")._get("height").cast())
        }),
      ])
      observer._call("observe", [parent]) |> ignore
      let blur = @core.any(fn() { finish(true) })
      @core.global_this()._call("addEventListener", [@core.any("blur"), blur])
      |> ignore
      fn() {
        observer._call("disconnect", []) |> ignore
        @core.global_this()._call("removeEventListener", [
          @core.any("blur"),
          blur,
        ])
        |> ignore
        // Release ownership without publishing state after the panel unmounts.
        finish(false)
      }
    },
    [],
  )
  let handle = h(
    "div",
    {
      "className": @core.any("timeline-resize"),
      "role": @core.any("separator"),
      "tabIndex": @core.any(0),
      "aria-label": @core.any("タイムラインの高さ"),
      "aria-orientation": @core.any("horizontal"),
      "aria-valuemin": @core.any(minimum),
      "aria-valuemax": @core.any(maximum),
      "aria-valuenow": @core.any(height),
      "aria-valuetext": @core.any("\{height.to_int()} px"),
      "title": @core.any("ドラッグまたは上下キーで高さを調整"),
      "onPointerDown": @core.any(fn(event : @core.Any) {
        if event._get("button").cast() != 0 || drag.get_current() is Some(_) {
          return
        }
        prevent_default(event)
        let target = event._get("currentTarget")
        let pointer : Int = event._get("pointerId").cast()
        target._call("focus", [
          host_record({ "preventScroll": @core.any(true) }),
        ])
        |> ignore
        target._call("setPointerCapture", [@core.any(pointer)]) |> ignore
        drag.set_current(
          Some({
            pointer,
            y: event._get("clientY").cast(),
            height,
            requested,
            element: target,
          }),
        )
      }),
      "onPointerMove": @core.any(fn(event : @core.Any) {
        if drag.get_current() is Some(current) &&
          event._get("pointerId").cast() == current.pointer {
          let y : Double = event._get("clientY").cast()
          set_requested(
            Some(@scene.clamp(current.height + current.y - y, minimum, maximum)),
          )
        }
      }),
      "onPointerUp": @core.any(fn(event : @core.Any) {
        if drag.get_current() is Some(current) &&
          event._get("pointerId").cast() == current.pointer {
          finish(false)
        }
      }),
      "onPointerCancel": @core.any(fn(event : @core.Any) {
        if drag.get_current() is Some(current) &&
          event._get("pointerId").cast() == current.pointer {
          finish(true)
        }
      }),
      "onLostPointerCapture": @core.any(fn() { finish(true) }),
      "onKeyDown": @core.any(fn(event : @core.Any) {
        let key : String = event._get("key").cast()
        if key == "Escape" && drag.get_current() is Some(_) {
          prevent_default(event)
          event._call("stopPropagation", []) |> ignore
          finish(true)
          return
        }
        let next = match key {
          "ArrowUp" => Some(height + 20.0)
          "ArrowDown" => Some(height - 20.0)
          "Home" => Some(minimum)
          "End" => Some(maximum)
          _ => None
        }
        if next is Some(next) {
          prevent_default(event)
          event._call("stopPropagation", []) |> ignore
          finish(false)
          set_requested(Some(@scene.clamp(next, minimum, maximum)))
        }
      }),
    },
    [h("span", { "aria-hidden": @core.any(true) }, [])],
  )
  { element, height, handle, }
}
