///|
fn composition_properties(
  controller : InspectorController,
  object : @core.Any,
  state : @scene.ObjectState,
) -> Array[&@react.ReactNode] {
  let kind = @boundary.read_object_kind(object._get("kind"))
  let media = kind is Image || kind is Video
  let content : Array[&@react.ReactNode] = []
  if !(kind is Text || kind is Equation) {
    content.push(
      inspector_section("Size", [
        h("div", { "className": @core.any("property-grid") }, [
          number_field(
            "W",
            "Width",
            state.width,
            fn(width) {
              let patch = { "width": @core.any(width) }
              if media {
                patch["height"] = @core.any(
                  state.height * width / state.width.max(1.0),
                )
              }
              controller.update(patch)
            },
            min=1.0,
          ),
          number_field(
            "H",
            "Height",
            state.height,
            fn(height) {
              let patch = { "height": @core.any(height) }
              if media {
                patch["width"] = @core.any(
                  state.width * height / state.height.max(1.0),
                )
              }
              controller.update(patch)
            },
            min=if media { 1.0 } else { -10000.0 },
          ),
        ]),
      ]),
    )
  }
  let asset = if kind is Image {
    object._get("image")
  } else if kind is Video {
    object._get("media")
  } else {
    @core.undefined()
  }
  if media && truthy(asset) {
    let width : Double = asset._get("width").cast()
    let height : Double = asset._get("height").cast()
    let dimensions = string_value(@core.any(width)) +
      " × " +
      string_value(@core.any(height)) +
      " px"
    let description = if kind is Video {
      dimensions +
      " · " +
      fixed_number(asset._get("duration").cast() / 1000.0, 2) +
      " s"
    } else {
      dimensions
    }
    content.push(
      inspector_section(if kind is Image { "Image" } else { "Video" }, [
        h("p", { "className": @core.any("muted small") }, [description]),
        inspector_button(
          "元の縦横比に戻す",
          "",
          fn() { controller.number("height", state.width * height / width) },
          class_name="text-button",
        ),
        h("p", { "className": @core.any("muted small") }, [
          if kind is Image {
            "角をドラッグして拡大縮小。Shift で縦横比を変更。"
          } else {
            "下の素材トラックで開始位置とトリミングを編集できます。音声は独立トラックです。"
          },
        ]),
      ]),
    )
  }
  if kind is Text || kind is Equation {
    let props = {
      "className": @core.any("content-input"),
      "aria-label": @core.any(
        if kind is Equation {
          "LaTeX expression"
        } else {
          "Text content"
        },
      ),
      "value": @core.any(state.text),
      "rows": @core.any(3),
      "spellCheck": @core.any(false),
    }
    let input = if kind is Equation {
      props["onChange"] = @core.any(fn(text : String) {
        controller.update({ "text": @core.any(text) })
      })
      component(tex_textarea, props, [])
    } else {
      props["onChange"] = @core.any(fn(event : @core.Any) {
        controller.update({ "text": event._get("target")._get("value") })
      })
      h("textarea", props, [])
    }
    content.push(
      inspector_section(if kind is Equation { "LaTeX" } else { "Text" }, [
        input,
        number_field(
          "Size",
          "Font size",
          state.fontSize,
          fn(size) {
            let patch = { "fontSize": @core.any(size) }
            if kind is Equation {
              patch["width"] = @core.any(
                state.width * size / state.fontSize.max(1.0),
              )
              patch["height"] = @core.any(
                state.height * size / state.fontSize.max(1.0),
              )
            }
            controller.update(patch)
          },
          min=8.0,
          max=400.0,
          suffix="px",
        ),
      ]),
    )
  }
  let visibility = component(
    icon_button,
    {
      "label": @core.any(
        if state.visible {
          "非表示にする"
        } else {
          "表示する"
        },
      ),
      "onClick": @core.any(fn() {
        controller.update({ "visible": @core.any(!state.visible) })
      }),
    },
    [icon(if state.visible { "Eye" } else { "EyeOff" }, 13)],
  )
  content.push(
    component(
      section,
      { "title": @core.any("Appearance"), "action": @core.any(visibility) },
      [
        h("div", { "className": @core.any("property-grid") }, [
          number_field(
            "◧",
            "Opacity",
            state.opacity * 100.0,
            fn(value) { controller.number("opacity", value / 100.0) },
            min=0.0,
            max=100.0,
            suffix="%",
          ),
          number_field(
            "⌜",
            "Corner radius",
            state.cornerRadius,
            fn(value) { controller.number("cornerRadius", value) },
            min=0.0,
          ),
        ]),
      ],
    ),
  )
  content.push(
    inspector_section("Effects", [
      component(field, { "label": @core.any("Effect") }, [
        h(
          "select",
          {
            "aria-label": @core.any("Object effect"),
            "value": @core.any(@scene.effect_name(state.effect)),
            "onChange": @core.any(fn(event : @core.Any) {
              controller.update({ "effect": event._get("target")._get("value") })
            }),
          },
          [export_choice("none", "None"), export_choice("glow", "Glow")],
        ),
      ]),
    ]),
  )
  if !(kind is Image) {
    let palette : Array[&@react.ReactNode] = []
    for
      color in [
        "#d7d8e4", "#67c4d9", "#f4ce55", "#b5d396", "#ef8078", "#d5a3bd", "#8a8fe9",
        "#ffffff",
      ] {
      palette.push(
        h(
          "button",
          {
            "key": @core.any(color),
            "aria-label": @core.any("色 " + color),
            "onClick": @core.any(fn() {
              controller.update({ "fill": @core.any(color) })
            }),
            "style": host_record({ "background": @core.any(color) }),
            "className": @core.any(
              if state.fill == color {
                "selected"
              } else {
                ""
              },
            ),
          },
          [],
        ),
      )
    }
    content.push(
      inspector_section("Fill", [
        component(
          color_input,
          {
            "value": @core.any(state.fill),
            "label": @core.any("Fill"),
            "onChange": @core.any(fn(color : String) {
              controller.update({ "fill": @core.any(color) })
            }),
          },
          [],
        ),
        h("div", { "className": @core.any("palette") }, palette),
      ]),
    )
  }
  content.push(
    inspector_section("Stroke", [
      component(
        color_input,
        {
          "value": @core.any(state.stroke),
          "label": @core.any("Stroke"),
          "onChange": @core.any(fn(color : String) {
            controller.update({ "stroke": @core.any(color) })
          }),
        },
        [],
      ),
      number_field(
        "Width",
        "Stroke width",
        state.strokeWidth,
        fn(value) { controller.number("strokeWidth", value) },
        min=0.0,
        max=100.0,
        suffix="px",
      ),
    ]),
  )
  content
}

///|
fn composition_inspector(
  controller : InspectorController,
  object : @core.Any,
  composition : @core.Any,
) -> Array[&@react.ReactNode] {
  let content : Array[&@react.ReactNode] = []
  if controller.selected.length() == 0 {
    content.push(
      inspector_section("Composition", [
        component(field, { "label": @core.any("Name") }, [
          h(
            "input",
            {
              "aria-label": @core.any("Composition name"),
              "value": composition._get("name"),
              "onChange": @core.any(fn(event : @core.Any) {
                controller.store._call("setComposition", [
                  @core.any(controller.scene_id),
                  @core.any(controller.composition_id),
                  host_record({ "name": event._get("target")._get("value") }),
                ])
                |> ignore
              }),
            },
            [],
          ),
        ]),
        number_field(
          "Hold",
          "Composition duration",
          composition._get("duration").cast(),
          fn(value) {
            controller.store._call("setComposition", [
              @core.any(controller.scene_id),
              @core.any(controller.composition_id),
              host_record({ "duration": @core.any(value) }),
            ])
            |> ignore
          },
          min=0.0,
          max=120000.0,
          suffix="ms",
        ),
      ]),
    )
    content.push(
      inspector_section("Canvas", [
        h("div", { "className": @core.any("canvas-dimensions") }, [
          h("span", Map([]), [
            string_value(controller.scene._get("width")) +
            " × " +
            string_value(controller.scene._get("height")),
          ]),
          h("span", { "className": @core.any("muted") }, ["16:9"]),
        ]),
        component(
          color_input,
          {
            "value": controller.scene._get("background"),
            "label": @core.any("Background"),
            "onChange": @core.any(fn(value : String) {
              controller.store._call("setScene", [
                @core.any(controller.scene_id),
                host_record({ "background": @core.any(value) }),
              ])
              |> ignore
            }),
          },
          [],
        ),
      ]),
    )
    content.push(
      h("div", { "className": @core.any("inspector-empty") }, [
        icon("Spline", 28),
        h("p", Map([]), [
          "オブジェクトを選んで",
          h("br", Map([]), []),
          "アイデアを形に",
        ]),
        h("span", Map([]), ["Shift + click で複数選択"]),
      ]),
    )
    return content
  }
  let state = if truthy(object) {
    @boundary.state_for(
      controller.scene,
      controller.composition_id,
      object._get("id").cast(),
    )
  } else {
    @core.undefined()
  }
  let decoded = if truthy(state) {
    Some(@boundary.read_object_state(state))
  } else {
    None
  }
  if decoded is Some(state) {
    content.push(
      inspector_section("Position", [
        h("div", { "className": @core.any("property-grid") }, [
          number_field("X", "Position X", state.x, fn(value) {
            controller.number("x", value)
          }),
          number_field("Y", "Position Y", state.y, fn(value) {
            controller.number("y", value)
          }),
        ]),
        h("div", { "className": @core.any("property-grid") }, [
          number_field(
            "↳",
            "Rotation",
            state.rotation,
            fn(value) { controller.number("rotation", value) },
            min=-360.0,
            max=360.0,
            suffix="°",
          ),
          h("div", { "className": @core.any("button-group") }, [
            component(
              icon_button,
              {
                "label": @core.any("90度回転"),
                "onClick": @core.any(fn() {
                  controller.number("rotation", (state.rotation + 90.0) % 360.0)
                }),
              },
              [icon("RotateCcw", 14)],
            ),
          ]),
        ]),
      ]),
    )
  }
  let alignment : Array[&@react.ReactNode] = []
  for
    (image, axis, position, label) in [
      ("AlignHorizontalJustifyStart", "x", @editor.AlignStart, "左揃え"),
      ("AlignHorizontalJustifyCenter", "x", @editor.AlignCenter, "左右中央"),
      ("AlignHorizontalJustifyEnd", "x", @editor.AlignEnd, "右揃え"),
      ("AlignVerticalJustifyStart", "y", @editor.AlignStart, "上揃え"),
      ("AlignVerticalJustifyCenter", "y", @editor.AlignCenter, "上下中央"),
      ("AlignVerticalJustifyEnd", "y", @editor.AlignEnd, "下揃え"),
    ] {
    alignment.push(
      component(
        icon_button,
        {
          "key": @core.any(label),
          "label": @core.any(label),
          "onClick": @core.any(fn() { controller.align(axis, position) }),
        },
        [icon(image, 14)],
      ),
    )
  }
  content.push(
    inspector_section(
      if controller.selected.length() > 1 {
        "Alignment"
      } else {
        "Align"
      },
      [h("div", { "className": @core.any("alignment-buttons") }, alignment)],
    ),
  )
  let order = @boundary.ordered_objects(controller.scene)
  let mut front = true
  let mut back = true
  for index, item in order {
    let id : String = item._get("id").cast()
    let chosen = controller.selected.iter().any(fn(value) { value == id })
    if index >= order.length() - controller.selected.length() && !chosen {
      front = false
    }
    if index < controller.selected.length() && !chosen {
      back = false
    }
  }
  content.push(
    inspector_section("Layer order", [
      inspector_button(
        "Bring to front",
        "ArrowUpToLine",
        fn() { controller.arrange(true) },
        disabled=front,
      ),
      inspector_button(
        "Send to back",
        "ArrowDownToLine",
        fn() { controller.arrange(false) },
        disabled=back,
      ),
    ]),
  )
  if decoded is Some(state) {
    for item in composition_properties(controller, object, state) {
      content.push(item)
    }
  }
  content.push(
    inspector_section("Actions", [
      h(
        "button",
        {
          "className": @core.any("subtle-button full-width"),
          "onClick": @core.any(fn() {
            if controller.can_edit() {
              let next = controller.store._call("duplicate", [
                @core.any(controller.scene_id),
                @core.any(controller.composition_id),
                @core.any(controller.selected),
              ])
              controller.editor._get("setSelectedIds")._invoke([next]) |> ignore
            }
          }),
        },
        [
          icon("Copy", 13),
          "Duplicate",
          h("span", { "className": @core.any("shortcut") }, ["⌘D"]),
        ],
      ),
      inspector_button(
        "Hide in this composition",
        "EyeOff",
        fn() {
          if controller.can_edit() {
            controller.store._call("hide", [
              @core.any(controller.scene_id),
              @core.any(controller.composition_id),
              @core.any(controller.selected),
            ])
            |> ignore
            controller.editor
            ._get("setSelectedIds")
            ._invoke([@core.any(([] : FixedArray[String]))])
            |> ignore
          }
        },
        class_name="text-button",
      ),
    ]),
  )
  content
}
