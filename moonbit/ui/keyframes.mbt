///|
fn keyframe_label(property : @scene.CurveProperty) -> String {
  match property {
    PositionX => "X"
    PositionY => "Y"
    ObjectAnchorX => "Anchor X"
    ObjectAnchorY => "Anchor Y"
    ObjectScaleX => "Scale X"
    ObjectScaleY => "Scale Y"
    ObjectShear => "Shear"
    _ => @scene.curve_property_name(property)
  }
}

///|
let keyframe_component : TypedComponent[KeyframeView] = memo_typed_component(
  keyframe_inspector,
)

///|
fn keyframe_inspector(input : KeyframeView) -> @react.Element {
  let animation = input.animation
  let binding = input.binding
  let track = animation.track
  let channel = input.channel
  let properties = @scene.curve_properties(channel)
  let (chosen, choose) = @react.use_state(@scene.PositionX)
  let property = if properties.contains(chosen) {
    chosen
  } else {
    properties[0]
  }
  let name = @scene.curve_property_name(property)
  let timing = animation.timing(channel)
  let disabled = input.disabled ||
    track.type_ == Cut ||
    timing.duration <= 0.0 ||
    !animation.keyframes_ready
  let (error, set_error) = @react.use_state("")
  let keys : Array[(String, @scene.Keyframe)] = []
  if track.keyframes is Some(values) {
    for id, key in values {
      if key.property == property && key.deleted != Some(true) {
        keys.push((id, key))
      }
    }
  }
  keys.sort_by(fn(a, b) {
    if a.1.at < b.1.at {
      -1
    } else if a.1.at > b.1.at {
      1
    } else {
      a.0.compare(b.0)
    }
  })
  let apply = fn(change : () -> Unit) {
    if disabled {
      return
    }
    attempt(
      fn() {
        change()
        set_error("")
      },
      set_error,
      "キーフレームを変更できませんでした。",
    )
  }
  let choices : Array[&@react.ReactNode] = []
  for p in properties {
    choices.push(
      export_choice(@scene.curve_property_name(p), keyframe_label(p)),
    )
  }
  let content : Array[&@react.ReactNode] = [
    component(field, { "label": @core.any("Keyframes") }, [
      h(
        "select",
        {
          "aria-label": @core.any("Keyframe property"),
          "value": @core.any(name),
          "onChange": @core.any(fn(event : @core.Any) {
            if @scene.curve_property(event._get("target")._get("value").cast())
              is Some(p) {
              choose(p)
              set_error("")
            }
          }),
        },
        choices,
      ),
    ]),
    h("p", { "className": @core.any("property-timing-note") }, [
      "両端は Composition に連動。中間点の時刻は、この属性の区間内の割合です。",
    ]),
  ]
  if track.type_ == Cut {
    content.push(
      h("p", { "className": @core.any("property-timing-note") }, [
        "Cut では中間点を使用しません。Move などに変更すると再び有効になります。",
      ]),
    )
  }
  let curve = (input.evaluation.curve)(property)
  let kernel = input.evaluation.kernel
  if curve is Some(curve) &&
    !(property is ObjectFill || property is ObjectStroke) {
    let values : Array[Double] = []
    for i = 0; i <= 64; i = i + 1 {
      if curve.evaluate(
          timing.start + timing.duration * i.to_double() / 64.0,
          kernel,
        )
        is CurveNumber(value) {
        values.push(value)
      }
    }
    let mut low = values[0]
    let mut high = low
    for value in values {
      low = low.min(value)
      high = high.max(value)
    }
    let range = (high - low).max(1.0)
    let path = StringBuilder()
    for i, value in values {
      path.write_string(if i == 0 { "M" } else { " L" })
      path.write_string(
        "\{8.0 + 224.0 * i.to_double() / 64.0} \{64.0 - (value - low) / range * 56.0}",
      )
    }
    content.push(
      h(
        "svg",
        {
          "viewBox": @core.any("0 0 240 72"),
          "className": @core.any("keyframe-graph"),
          "role": @core.any("img"),
          "aria-label": @core.any(keyframe_label(property) + " value curve"),
        },
        [
          h(
            "path",
            {
              "d": @core.any(path.to_string()),
              "fill": @core.any("none"),
              "stroke": @core.any("#a8a6ff"),
              "strokeWidth": @core.any(2),
            },
            [],
          ),
        ],
      ),
    )
  }
  for index, (id, key) in keys {
    let label = keyframe_label(property) + " keyframe \{index + 1}"
    let value_input = match key.value {
      CurveNumber(value) =>
        number_field(
          "Value",
          label + " value",
          value,
          fn(value) {
            apply(fn() { binding.set_keyframe_value(id, CurveNumber(value)) })
          },
          min=if property is ObjectOpacity ||
            property is ObjectReveal ||
            property is ObjectStrokeWidth ||
            property is ObjectFontSize ||
            property is ObjectCornerRadius {
            0.0
          } else {
            -100000.0
          },
          max=if property is ObjectOpacity || property is ObjectReveal {
            1.0
          } else {
            100000.0
          },
        )
      CurveColor(value) =>
        component(
          color_input,
          {
            "label": @core.any(label + " value"),
            "value": @core.any(value),
            "onChange": @core.any(fn(value : String) {
              apply(fn() { binding.set_keyframe_value(id, CurveColor(value)) })
            }),
          },
          [],
        )
    }
    content.push(
      h(
        "div",
        {
          "key": @core.any(id),
          "className": @core.any("keyframe-row"),
          "data-keyframe-id": @core.any(id),
        },
        [
          h("div", { "className": @core.any("keyframe-values") }, [
            number_field(
              "Time",
              label + " time",
              key.at * 100.0,
              fn(value) {
                apply(fn() { binding.set_keyframe_at(id, value / 100.0) })
              },
              min=0.001,
              max=99.999,
              suffix="%",
            ),
            value_input,
          ]),
          typed_component(easing_component, {
            value: Some(key.easing),
            label: label + " outgoing easing",
            disabled,
            disabled_reason: None,
            current: Some(fn() { binding.keyframe_easing(id) }),
            on_change: fn(value, separate) {
              apply(fn() { binding.set_keyframe_easing(id, value, separate) })
            },
          }),
          inspector_button(
            "中間点を削除",
            "Trash2",
            fn() { apply(fn() { binding.remove_keyframe(id) }) },
            class_name="text-button",
            disabled~,
          ),
        ],
      ),
    )
  }
  content.push(
    inspector_button(
      "中間点を追加",
      "Plus",
      fn() {
        // Split the largest free interval so repeated additions remain reachable.
        let mut start = 0.0
        let mut gap = 0.0
        let mut at = 0.5
        for end in keys.map(fn(k) { k.1.at }) + [1.0] {
          if end - start > gap {
            gap = end - start
            at = (start + end) / 2.0
          }
          start = end
        }
        if gap < 0.00002 {
          return
        }
        let value = match curve {
          Some(curve) =>
            curve.evaluate(timing.start + at * timing.duration, kernel)
          None =>
            (input.evaluation.sample)(
              property,
              timing.start + at * timing.duration,
              at,
            )
        }
        apply(fn() {
          binding.add_keyframe({
            property,
            at,
            value,
            easing: timing.easing,
            deleted: None,
          })
        })
      },
      disabled~,
    ),
  )
  if !error.is_empty() {
    content.push(
      h(
        "p",
        {
          "role": @core.any("alert"),
          "className": @core.any("property-timing-error"),
        },
        [error],
      ),
    )
  }
  h(
    "fieldset",
    {
      "disabled": @core.any(disabled),
      "className": @core.any("keyframe-fields"),
    },
    content,
  )
}
