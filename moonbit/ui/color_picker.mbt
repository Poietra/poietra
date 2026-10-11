///|
priv struct ColorDrag {
  pointer : Int
  element : @core.Any
  before : UndoEntry?
  mut undo : UndoEntry?
  mut last : String
}

///|
priv struct ColorPickerView {
  value : String
  color : PickerColor
  disabled : Bool
  change : (String, Bool) -> Unit
}

///|
priv struct ColorPickerController {
  history : GestureHistory
  latest : @react.ReactRef[ColorPickerView]
  drag : @react.ReactRef[ColorDrag]
  set_color : (PickerColor?) -> Unit
  notify : (String) -> Unit
}

///|
fn ColorPickerController::finish(
  self : ColorPickerController,
  cancel : Bool,
) -> Unit {
  guard self.drag.get_current() is Some(drag) else { return }
  self.drag.set_current(None)
  @core.throwable(fn() {
    if cancel &&
      drag.undo is Some(entry) &&
      drag.undo != drag.before &&
      self.history.top() == drag.undo {
      self.history.rollback(entry)
      (self.set_color)(None)
    }
  }) catch {
    failure =>
      (self.notify)(
        error_message(
          ui_native_error(failure),
          "色の変更を取り消せませんでした。",
        ),
      )
  }
  self.history.end()
  @core.throwable(fn() {
    if drag.element._call("hasPointerCapture", [@core.any(drag.pointer)]).cast() {
      drag.element._call("releasePointerCapture", [@core.any(drag.pointer)])
      |> ignore
    }
  }) catch {
    _ => ()
  }
}

///|
fn ColorPickerController::apply(
  self : ColorPickerController,
  color : PickerColor,
) -> Unit {
  let view = self.latest.get_current().unwrap()
  if view.disabled {
    self.finish(true)
    return
  }
  if self.drag.get_current() is Some(drag) {
    if drag.last != view.value.to_lower() {
      self.finish(true)
      return
    }
    if drag.undo is Some(_) && self.history.top() != drag.undo {
      self.finish(false)
      return
    }
  }
  let value = color.hex()
  (self.set_color)(Some(color))
  self.latest.set_current(Some({ ..view, value, color, }))
  if value != view.value.to_lower() {
    (view.change)(value, self.drag.get_current() is None)
    if self.drag.get_current() is Some(drag) {
      drag.last = value
      drag.undo = self.history.top()
    }
  }
}

///|
fn ColorPickerController::begin(
  self : ColorPickerController,
  event : @core.Any,
) -> Unit {
  let view = self.latest.get_current().unwrap()
  if view.disabled ||
    event._get("button").cast() != 0 ||
    self.drag.get_current() is Some(_) {
    return
  }
  let element = event._get("currentTarget")
  let pointer : Int = event._get("pointerId").cast()
  element._call("focus", []) |> ignore
  self.history.begin()
  self.drag.set_current(
    Some({
      pointer,
      element,
      before: self.history.top(),
      undo: None,
      last: view.value.to_lower(),
    }),
  )
  @core.throwable(fn() {
    element._call("setPointerCapture", [@core.any(pointer)]) |> ignore
  }) catch {
    _ => self.finish(true)
  }
}

///|
fn ColorPickerController::pointer_move(
  self : ColorPickerController,
  event : @core.Any,
) -> Unit {
  guard self.drag.get_current() is Some(drag) &&
    drag.pointer == event._get("pointerId").cast() else {
    return
  }
  let rect = drag.element._call("getBoundingClientRect", [])
  let width : Double = rect._get("width").cast()
  let height : Double = rect._get("height").cast()
  if width <= 0.0 || height <= 0.0 {
    return
  }
  let x : Double = event._get("clientX").cast()
  let y : Double = event._get("clientY").cast()
  let left : Double = rect._get("left").cast()
  let top : Double = rect._get("top").cast()
  let color = self.latest.get_current().unwrap().color
  self.apply({
    ..color,
    saturation: @scene.clamp((x - left) / width, 0.0, 1.0),
    brightness: @scene.clamp(1.0 - (y - top) / height, 0.0, 1.0),
  })
}

///|
fn color_picker(input : @core.Any) -> @react.Element {
  let value : String = input._get("value").cast()
  let label : String = input._get("label").cast()
  let disabled = truthy(input._get("disabled"))
  let change : (String, Bool) -> Unit = input._get("onChange").cast()
  let editor = use_editor_state()
  let (open, set_open) = @react.use_state(false)
  let (chosen, set_color) = @react.use_state((None : PickerColor?))
  let color = match chosen {
    Some(color) if color.hex() == value.to_lower() => color
    _ => picker_color(value)
  }
  let latest = @react.use_ref(
    Some(ColorPickerView::{ value, color, disabled, change, }),
  )
  latest.set_current(Some({ value, color, disabled, change, }))
  let drag = @react.use_ref((None : ColorDrag?))
  let eyedropper = @react.use_ref((None : @core.Any?))
  let (picking, set_picking) = @react.use_state(false)
  let controller : ColorPickerController = {
    history: native_gesture_history(editor.store),
    latest,
    drag,
    set_color,
    notify: editor.actions.notify,
  }
  @react.use_effect(
    fn() {
      if disabled {
        set_open(false)
        set_picking(false)
      }
      let window = @core.global_this()._get("window")
      let cancel = fn() { controller.finish(true) }
      window._call("addEventListener", [@core.any("blur"), @core.any(cancel)])
      |> ignore
      fn() {
        window._call("removeEventListener", [
          @core.any("blur"),
          @core.any(cancel),
        ])
        |> ignore
        controller.finish(true)
        if eyedropper.get_current() is Some(request) {
          request._call("abort", []) |> ignore
          eyedropper.set_current(None)
        }
      }
    },
    [editor.store, @core.any(disabled), @core.any(open)],
  )
  let end = fn(event : @core.Any, cancel : Bool) {
    if drag.get_current() is Some(active) &&
      active.pointer == event._get("pointerId").cast() {
      controller.finish(cancel)
    }
  }
  let rgb = picker_rgb(value)
  let fields : Array[&@react.ReactNode] = []
  for (index, channel) in [(0, "R"), (1, "G"), (2, "B")] {
    fields.push(
      h("label", Map([]), [
        h("span", Map([]), [channel]),
        component(
          number_input,
          {
            "label": @core.any(label + " " + channel),
            "value": @core.any(rgb[index]),
            "min": @core.any(0),
            "max": @core.any(255),
            "step": @core.any(1),
            "onChange": @core.any(fn(next : Double) {
              let channels = picker_rgb(latest.get_current().unwrap().value)
              channels[index] = @scene.clamp(next, 0.0, 255.0).to_int()
              controller.apply(picker_color(picker_hex(channels)))
            }),
          },
          [],
        ),
      ]),
    )
  }
  let tools : Array[&@react.ReactNode] = [
    h(
      "span",
      {
        "className": @core.any("color-picker-preview"),
        "style": host_record({ "background": @core.any(value) }),
        "aria-hidden": @core.any(true),
      },
      [],
    ),
    h("span", { "className": @core.any("color-picker-code") }, [
      value.to_upper(),
    ]),
  ]
  if eye_dropper_available() {
    tools.push(
      h(
        "button",
        {
          "type": @core.any("button"),
          "className": @core.any("icon-button"),
          "aria-label": @core.any("画面から色を取得"),
          "disabled": @core.any(picking),
          "onClick": @core.any(fn() {
            set_picking(true)
            let request = open_eye_dropper(
              fn(hex) { controller.apply(picker_color(hex)) },
              fn() {
                set_picking(false)
                eyedropper.set_current(None)
              },
            )
            eyedropper.set_current(Some(request))
          }),
        },
        [icon("Pipette", 16)],
      ),
    )
  }
  ui(
    "Popover",
    "Root",
    {
      "open": @core.any(open && !disabled),
      "onOpenChange": @core.any(fn(next : Bool) {
        controller.finish(true)
        set_open(next && !disabled)
        set_picking(false)
      }),
    },
    [
      ui(
        "Popover",
        "Trigger",
        {
          "className": @core.any("color-swatch"),
          "aria-label": @core.any(label + "の色を選択"),
          "disabled": @core.any(disabled),
          "style": host_record({ "background": @core.any(value) }),
        },
        [],
      ),
      ui("Popover", "Portal", Map([]), [
        ui(
          "Popover",
          "Positioner",
          {
            "sideOffset": @core.any(8),
            "align": @core.any("end"),
            "className": @core.any("color-picker-positioner"),
          },
          [
            ui(
              "Popover",
              "Popup",
              {
                "className": @core.any("color-picker-popup"),
                "aria-label": @core.any(label + "の色を選択"),
              },
              [
                h("div", { "className": @core.any("color-picker-heading") }, [
                  h("h2", Map([]), [label]),
                  ui(
                    "Popover",
                    "Close",
                    {
                      "className": @core.any("icon-button"),
                      "aria-label": @core.any(
                        "カラーパレットを閉じる",
                      ),
                    },
                    [icon("X", 14)],
                  ),
                ]),
                h(
                  "div",
                  {
                    "className": @core.any("color-picker-plane"),
                    "role": @core.any("slider"),
                    "tabIndex": @core.any(0),
                    "aria-label": @core.any(label + "の彩度と明度"),
                    "aria-valuemin": @core.any(0),
                    "aria-valuemax": @core.any(100),
                    "aria-valuenow": @core.any(
                      (color.saturation * 100.0).to_int(),
                    ),
                    "aria-valuetext": @core.any(
                      "彩度 \{(color.saturation * 100.0).to_int()}%、明度 \{(color.brightness * 100.0).to_int()}%",
                    ),
                    "style": host_record({
                      "backgroundColor": @core.any("hsl(\{color.hue} 100% 50%)"),
                    }),
                    "onPointerDown": @core.any(fn(event : @core.Any) {
                      controller.begin(event)
                      prevent_default(event)
                      controller.pointer_move(event)
                    }),
                    "onPointerMove": @core.any(fn(event : @core.Any) {
                      controller.pointer_move(event)
                    }),
                    "onPointerUp": @core.any(fn(event : @core.Any) {
                      end(event, false)
                    }),
                    "onPointerCancel": @core.any(fn(event : @core.Any) {
                      end(event, true)
                    }),
                    "onLostPointerCapture": @core.any(fn(event : @core.Any) {
                      end(event, true)
                    }),
                    "onKeyDown": @core.any(fn(event : @core.Any) {
                      let key : String = event._get("key").cast()
                      let current = latest.get_current().unwrap().color
                      let step = if truthy(event._get("shiftKey")) {
                        0.1
                      } else {
                        0.01
                      }
                      let next = match key {
                        "ArrowLeft" =>
                          Some({
                            ..current,
                            saturation: (current.saturation - step).max(0.0),
                          })
                        "ArrowRight" =>
                          Some({
                            ..current,
                            saturation: (current.saturation + step).min(1.0),
                          })
                        "ArrowDown" =>
                          Some({
                            ..current,
                            brightness: (current.brightness - step).max(0.0),
                          })
                        "ArrowUp" =>
                          Some({
                            ..current,
                            brightness: (current.brightness + step).min(1.0),
                          })
                        _ => None
                      }
                      if next is Some(next) {
                        prevent_default(event)
                        controller.apply(next)
                      }
                    }),
                  },
                  [
                    h(
                      "span",
                      {
                        "className": @core.any("color-picker-handle"),
                        "style": host_record({
                          "left": @core.any("\{color.saturation * 100.0}%"),
                          "top": @core.any(
                            "\{(1.0 - color.brightness) * 100.0}%",
                          ),
                          "background": @core.any(value),
                        }),
                      },
                      [],
                    ),
                  ],
                ),
                h(
                  "input",
                  {
                    "className": @core.any("color-picker-hue"),
                    "type": @core.any("range"),
                    "aria-label": @core.any(label + "の色相"),
                    "min": @core.any(0),
                    "max": @core.any(360),
                    "step": @core.any(1),
                    "value": @core.any(color.hue),
                    "onChange": @core.any(fn(event : @core.Any) {
                      controller.apply({
                        ..latest.get_current().unwrap().color,
                        hue: number_value(
                          event._get("target")._get("value").cast(),
                        ),
                      })
                    }),
                    "onPointerDown": @core.any(fn(event : @core.Any) {
                      controller.begin(event)
                    }),
                    "onPointerUp": @core.any(fn(event : @core.Any) {
                      end(event, false)
                    }),
                    "onPointerCancel": @core.any(fn(event : @core.Any) {
                      end(event, true)
                    }),
                    "onLostPointerCapture": @core.any(fn(event : @core.Any) {
                      end(event, true)
                    }),
                  },
                  [],
                ),
                h(
                  "div",
                  { "className": @core.any("color-picker-tools") },
                  tools,
                ),
                h("div", { "className": @core.any("color-picker-rgb") }, fields),
              ],
            ),
          ],
        ),
      ]),
    ],
  )
}
