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
fn keyframe_inspector(input : @core.Any) -> @react.Element {
  let editor = use_editor_state()
  let scene = editor._get("scene")
  let store = editor._get("store")
  let transition = input._get("transition")
  let object = input._get("object")
  let track = @boundary.read_track(input._get("track"))
  let channel = @scene.property_channel(input._get("channel").cast()).unwrap()
  let properties = @scene.curve_properties(channel)
  let (chosen, choose) = @react.use_state(@scene.PositionX)
  let property = if properties.contains(chosen) {
    chosen
  } else {
    properties[0]
  }
  let name = @scene.curve_property_name(property)
  let sid : String = scene._get("id").cast()
  let tid : String = transition._get("id").cast()
  let oid : String = object._get("id").cast()
  let timing = @scene.timing_override(track, channel).unwrap_or({
    start: track.start,
    duration: track.duration,
    easing: track.easing,
  })
  let disabled = truthy(input._get("disabled")) ||
    track.type_ == Cut ||
    timing.duration <= 0.0 ||
    !truthy(transition._get("tracks")._get(oid)._get("keyframes"))
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
  let apply = fn(id : String, patch : @core.Any, separate : Bool) {
    if disabled {
      return
    }
    attempt(
      fn() {
        store._call("setKeyframe", [
          @core.any(sid),
          @core.any(tid),
          @core.any(oid),
          @core.any(id),
          patch,
          @core.any(separate),
        ])
        |> ignore
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
  let curve = @boundary.keyframe_curve(scene, transition, oid, property)
  let kernel = @boundary.read_kernel(editor._get("kernel"))
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
            apply(id, host_record({ "value": @core.any(value) }), true)
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
              apply(id, host_record({ "value": @core.any(value) }), true)
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
                apply(id, host_record({ "at": @core.any(value / 100.0) }), true)
              },
              min=0.001,
              max=99.999,
              suffix="%",
            ),
            value_input,
          ]),
          component(
            easing_editor,
            {
              "value": @boundary.write_easing(key.easing),
              "label": @core.any(label + " outgoing easing"),
              "disabled": @core.any(disabled),
              "onChange": @core.any(fn(
                value : @core.Any,
                separate : @core.Any,
              ) {
                apply(
                  id,
                  host_record({ "easing": value }),
                  @core.is_undefined(separate) || truthy(separate),
                )
              }),
            },
            [],
          ),
          inspector_button(
            "中間点を削除",
            "Trash2",
            fn() { apply(id, @core.null(), true) },
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
          None => {
            let frame = @boundary.transition_frame(
              scene,
              transition,
              timing.start + at * timing.duration,
              editor._get("kernel"),
              @core.undefined(),
            )
            let objects : FixedArray[@core.Any] = frame._get("objects").cast()
            let item = objects
              .iter()
              .find_first(fn(item) {
                string_value(item._get("object")._get("id")) == oid
              })
            match item {
              Some(item) =>
                if property is ObjectReveal {
                  @scene.CurveNumber(at)
                } else {
                  @scene.state_curve_value(
                    @boundary.read_object_state(item._get("state")),
                    property,
                  )
                }
              None =>
                @scene.state_curve_value(
                  @scene.default_state(
                    @boundary.read_object_kind(object._get("kind")),
                  ),
                  property,
                )
            }
          }
        }
        apply(
          @boundary.new_id("key"),
          @boundary.write_keyframe({
            property,
            at,
            value,
            easing: timing.easing,
            deleted: None,
          }),
          true,
        )
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
