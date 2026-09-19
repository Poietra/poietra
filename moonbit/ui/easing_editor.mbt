///|
fn curve_handle(
  controller : CurveController,
  editor_node : @react.ReactRef[@core.Any],
  label : String,
  point : @editor.CurvePoint,
  x : Double,
  y : Double,
  disabled : Bool,
) -> @react.Element {
  let index = if point == First { 1 } else { 2 }
  h(
    "button",
    {
      "key": @core.any(index),
      "type": @core.any("button"),
      "className": @core.any("easing-control-point"),
      "aria-label": @core.any("\{label} control point \{index}"),
      "title": @core.any("Control point \{index} · \{x}, \{y}"),
      "disabled": @core.any(disabled),
      "style": @core.from_entries([
        ("left", @core.any("\{x * 100.0}%")),
        ("top", @core.any("\{(1.0 - y) * 100.0}%")),
      ]),
      "onPointerDown": @core.any(fn(event : @core.Any) {
        controller.down(event, point)
      }),
      "onPointerMove": @core.any(fn(event : @core.Any) {
        controller.pointer_move(event)
      }),
      "onPointerUp": @core.any(fn(event : @core.Any) {
        controller.end(event, false)
      }),
      "onPointerCancel": @core.any(fn(event : @core.Any) {
        controller.end(event, true)
      }),
      "onLostPointerCapture": @core.any(fn(event : @core.Any) {
        controller.end(event, true)
      }),
      "onClick": @core.any(fn() {
        if controller.ignore_click.get_current() == Some(true) {
          controller.ignore_click.set_current(Some(false))
          return
        }
        if editor_node.get_current() is Some(element) {
          let input = element._call("querySelector", [
            @core.any("[data-easing-coordinate=\"x\{index}\"] input"),
          ])
          if truthy(input) {
            input._call("focus", []) |> ignore
          }
        }
      }),
    },
    [h("span", Map([]), [index])],
  )
}

///|
pub fn easing_editor(input : @core.Any) -> @react.Element {
  let editor = use_editor()
  let plot = @react.use_ref((None : @core.Any?))
  let editor_node = @react.use_ref((None : @core.Any?))
  let gesture = @react.use_ref((None : CurveGesture?))
  let latest = @react.use_ref(Some(input))
  latest.set_current(Some(input))
  let ignore_click = @react.use_ref(Some(false))
  let description = @react.use_id()
  let controller : CurveController = {
    store: editor._get("store"),
    notify: editor._get("notify"),
    latest,
    plot,
    gesture,
    ignore_click,
  }
  let value = input._get("value")
  let curve = if @core.is_nullish(value) {
    None
  } else {
    Some(@boundary.read_easing(value))
  }
  let custom = curve is Some(CubicBezier(_, _, _, _))
  let disabled = truthy(input._get("disabled"))
  let label : String = input._get("label").cast()
  @react.use_effect(
    fn() {
      let cancel = fn() { controller.finish(true) }
      let key = fn(event : @core.Any) {
        if @core.equal(event._get("key"), @core.any("Escape")) &&
          gesture.get_current() is Some(_) {
          prevent_default(event)
          event._call("stopImmediatePropagation", []) |> ignore
          cancel()
        }
      }
      let window = @core.global_this()._get("window")
      window._call("addEventListener", [
        @core.any("keydown"),
        @core.any(key),
        @core.any(true),
      ])
      |> ignore
      window._call("addEventListener", [@core.any("blur"), @core.any(cancel)])
      |> ignore
      fn() {
        window._call("removeEventListener", [
          @core.any("keydown"),
          @core.any(key),
          @core.any(true),
        ])
        |> ignore
        window._call("removeEventListener", [
          @core.any("blur"),
          @core.any(cancel),
        ])
        |> ignore
        cancel()
      }
    },
    [editor._get("store"), @core.any(disabled), @core.any(custom)],
  )
  let options : Array[&@react.ReactNode] = []
  if curve is None {
    options.push(export_choice("", "Mixed", disabled=true))
  }
  for
    (value, name) in [
      ("linear", "Linear"),
      ("easeInOut", "Ease in out"),
      ("easeIn", "Ease in"),
      ("easeOut", "Ease out"),
      ("custom", "Custom Bézier"),
    ] {
    options.push(export_choice(value, name))
  }
  let nodes : Array[&@react.ReactNode] = [
    component(field, { "label": @core.any("Easing") }, [
      h(
        "select",
        {
          "aria-label": @core.any(label),
          "aria-describedby": if truthy(input._get("disabledReason")) {
            @core.any(description)
          } else {
            @core.undefined()
          },
          "disabled": @core.any(disabled),
          "value": if custom {
            @core.any("custom")
          } else if @core.typeof_(value) == "string" {
            value
          } else {
            @core.any("")
          },
          "onChange": @core.any(fn(event : @core.Any) {
            if !disabled {
              let value = event._get("target")._get("value")
              input
              ._get("onChange")
              ._invoke([
                if @core.equal(value, @core.any("custom")) {
                  @boundary.write_easing(
                    @scene.CubicBezier(0.25, 0.1, 0.25, 1.0),
                  )
                } else {
                  value
                },
              ])
              |> ignore
            }
          }),
        },
        options,
      ),
    ]),
  ]
  if curve is Some(curve) {
    let paths : Array[&@react.ReactNode] = [
      h(
        "path",
        {
          "className": @core.any("easing-curve-grid"),
          "d": @core.any("M0 50H100 M50 0V100 M0 100L100 0"),
        },
        [],
      ),
    ]
    if curve is CubicBezier(x1, y1, x2, y2) {
      paths.push(
        h(
          "path",
          {
            "className": @core.any("easing-control-lines"),
            "d": @core.any(
              "M0 100L\{x1 * 100.0} \{100.0 - y1 * 100.0} M100 0L\{x2 * 100.0} \{100.0 - y2 * 100.0}",
            ),
          },
          [],
        ),
      )
    }
    paths.push(
      h(
        "path",
        {
          "className": @core.any("easing-curve-line"),
          "d": @core.any(@editor.easing_curve_path(curve)),
        },
        [],
      ),
    )
    let graph : Array[&@react.ReactNode] = [
      h(
        "svg",
        {
          "viewBox": @core.any("0 0 100 100"),
          "preserveAspectRatio": @core.any("none"),
          "role": @core.any("img"),
          "aria-label": @core.any(label + " curve"),
        },
        paths,
      ),
    ]
    if curve is CubicBezier(x1, y1, x2, y2) {
      graph.push(
        curve_handle(controller, editor_node, label, First, x1, y1, disabled),
      )
      graph.push(
        curve_handle(controller, editor_node, label, Second, x2, y2, disabled),
      )
    }
    let panel : Array[&@react.ReactNode] = []
    if custom {
      panel.push(
        h("div", { "className": @core.any("easing-axis-label") }, [
          "Progress ↑",
        ]),
      )
    }
    panel.push(
      h(
        "div",
        { "ref": plot.as_any(), "className": @core.any("easing-curve-plot") },
        graph,
      ),
    )
    if custom {
      panel.push(
        h(
          "div",
          { "className": @core.any("easing-axis-label easing-time-label") },
          [
            h("span", Map([]), ["0"]),
            h("span", Map([]), ["Time →"]),
            h("span", Map([]), ["1"]),
          ],
        ),
      )
    }
    nodes.push(
      h(
        "div",
        {
          "className": @core.any(
            "easing-curve-panel" +
            (if custom { " is-custom" } else { "" }) +
            (if disabled { " is-disabled" } else { "" }),
          ),
        },
        panel,
      ),
    )
  }
  if curve is Some(CubicBezier(x1, y1, x2, y2)) {
    let coordinates : Array[&@react.ReactNode] = [
      h("legend", Map([]), ["Control points"]),
    ]
    for
      (key, name, coordinate, value) in [
        ("x1", "X1", @editor.X1, x1),
        ("y1", "Y1", @editor.Y1, y1),
        ("x2", "X2", @editor.X2, x2),
        ("y2", "Y2", @editor.Y2, y2),
      ] {
      coordinates.push(
        h(
          "div",
          { "data-easing-coordinate": @core.any(key), "key": @core.any(key) },
          [
            component(field, { "label": @core.any(name) }, [
              component(
                number_input,
                {
                  "value": @core.any(value),
                  "onChange": @core.any(fn(next : Double) {
                    controller.coordinate(coordinate, next)
                  }),
                  "label": @core.any(label + " " + name),
                  "min": @core.any(0),
                  "max": @core.any(1),
                  "step": @core.any(0.01),
                },
                [],
              ),
            ]),
          ],
        ),
      )
    }
    nodes.push(
      h(
        "fieldset",
        {
          "disabled": @core.any(disabled),
          "className": @core.any("easing-coordinates"),
        },
        coordinates,
      ),
    )
  }
  if custom && !disabled {
    nodes.push(
      h("p", { "className": @core.any("easing-editor-note") }, [
        "制御点をドラッグ、または数値で調整。Esc でドラッグを取り消せます。",
      ]),
    )
  }
  if truthy(input._get("disabledReason")) {
    nodes.push(
      h(
        "p",
        {
          "id": @core.any(description),
          "className": @core.any("easing-editor-note"),
        },
        [HostNode::{ value: input._get("disabledReason"), }],
      ),
    )
  }
  h(
    "div",
    { "ref": editor_node.as_any(), "className": @core.any("easing-editor") },
    nodes,
  )
}
