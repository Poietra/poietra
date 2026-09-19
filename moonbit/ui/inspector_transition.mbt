///|
fn transition_inspector(
  controller : InspectorController,
  object : @core.Any,
  transition : @core.Any,
  locked : Bool,
) -> Array[&@react.ReactNode] {
  let scene = controller.scene
  let store = controller.store
  let transition_id : String = transition._get("id").cast()
  let duration : Double = transition._get("duration").cast()
  let tracks = transition._get("tracks")
  let mut minimum = 100.0
  for id in @core.object_keys(tracks) {
    let track = tracks._get(id)
    let object = scene._get("objects")._get(track._get("objectId").cast())
    if truthy(object) && truthy(object._get("locked")) {
      minimum = @scene.maximum(
        minimum,
        @boundary.track_timing_end(track, !truthy(track._get("implicit"))),
      )
    }
  }
  let content : Array[&@react.ReactNode] = [
    inspector_section("Transition", [
      number_field(
        "Duration",
        "Transition duration",
        duration,
        fn(value) {
          if controller.can_edit() {
            store._call("setTransitionDuration", [
              @core.any(controller.scene_id),
              @core.any(transition_id),
              @core.any(value),
            ])
            |> ignore
          }
        },
        min=minimum,
        max=120000.0,
        suffix="ms",
      ),
    ]),
  ]
  if !truthy(object) {
    content.push(
      h("div", { "className": @core.any("inspector-empty") }, [
        icon("Spline", 28),
        h("p", Map([]), [
          "レイヤーを選択して",
          h("br", Map([]), []),
          "個々の動きを調整",
        ]),
      ]),
    )
    return content
  }
  let object_id : String = object._get("id").cast()
  let from_id : String = transition._get("fromId").cast()
  let to_id : String = transition._get("toId").cast()
  let from = @boundary.state_for(scene, from_id, object_id)
  let to = @boundary.state_for(scene, to_id, object_id)
  let from_visible = truthy(from) && truthy(from._get("visible"))
  let to_visible = truthy(to) && truthy(to._get("visible"))
  let entering = !from_visible && to_visible
  let leaving = from_visible && !to_visible
  let stored = tracks._get(object_id)
  let animation = @boundary.visible_animation(scene, transition, object_id)
  let native = if truthy(animation) {
    animation._get("track")
  } else {
    @boundary.default_track(
      object_id,
      host_record({ "duration": @core.any(duration) }),
    )
  }
  let timing = @boundary.read_track(native)
  let set_track = fn(patch : Map[String, @core.Any], separate : Bool) {
    if controller.can_edit() {
      store._call("setTrack", [
        @core.any(controller.scene_id),
        @core.any(transition_id),
        @core.any(object_id),
        host_record(patch),
        @core.any(separate),
      ])
      |> ignore
    }
  }
  let options : Array[&@react.ReactNode] = []
  for name in ["move", "write", "fade", "grow", "none"] {
    options.push(export_choice(name, animation_label(@core.any(name))))
  }
  let animation_fields : Array[&@react.ReactNode] = [
    component(field, { "label": @core.any("Type") }, [
      h(
        "select",
        {
          "aria-label": @core.any("Animation type"),
          "value": @core.any(@scene.animation_name(timing.type_)),
          "onChange": @core.any(fn(event : @core.Any) {
            set_track({ "type": event._get("target")._get("value") }, true)
          }),
        },
        options,
      ),
    ]),
  ]
  if timing.type_ is Write {
    animation_fields.push(
      component(field, { "label": @core.any("Order") }, [
        h(
          "select",
          {
            "aria-label": @core.any("Write order"),
            "value": @core.any(timing.order),
            "onChange": @core.any(fn(event : @core.Any) {
              set_track({ "order": event._get("target")._get("value") }, true)
            }),
          },
          [
            export_choice("together", "Together"),
            export_choice("sequential", "Sequential"),
          ],
        ),
      ]),
    )
  }
  if !truthy(stored) || truthy(stored._get("implicit")) {
    animation_fields.push(
      inspector_button("Add animation", "Plus", fn() {
        set_track(
          { "type": @core.any(if entering { "write" } else { "move" }) },
          true,
        )
      }),
    )
  }
  content.push(
    inspector_section(
      if entering {
        "Enter"
      } else if leaving {
        "Exit"
      } else {
        "Animation"
      },
      animation_fields,
    ),
  )
  let key = "\{controller.scene_id}/\{transition_id}/\{object_id}"
  let playing = truthy(controller.editor._get("playing"))
  content.push(
    inspector_section("Timing", [
      number_field(
        "Start",
        "Animation start",
        timing.start,
        fn(value) {
          set_track(
            {
              "start": @core.any(value),
              "duration": @core.any(
                @scene.minimum(timing.duration, duration - value),
              ),
            },
            true,
          )
        },
        min=0.0,
        max=(duration - 1.0).max(0.0),
        suffix="ms",
      ),
      number_field(
        "Duration",
        "Animation duration",
        timing.duration,
        fn(value) { set_track({ "duration": @core.any(value) }, true) },
        min=0.0,
        max=duration - timing.start,
        suffix="ms",
      ),
      component(
        easing_editor,
        {
          "key": @core.any(key),
          "value": @boundary.write_easing(timing.easing),
          "label": @core.any("Easing"),
          "onChange": @core.any(fn(value : @core.Any, separate : @core.Any) {
            set_track(
              { "easing": value },
              @core.is_undefined(separate) || truthy(separate),
            )
          }),
          "getValue": @core.any(fn() {
            let current = store
              ._call("project", [])
              ._get("scenes")
              ._get(controller.scene_id)
            if !truthy(current) {
              return @core.undefined()
            }
            let latest = current._get("transitions")._get(transition_id)
            if !truthy(latest) {
              return @core.undefined()
            }
            let value = @boundary.visible_animation(current, latest, object_id)
            if truthy(value) {
              value._get("track")._get("easing")
            } else {
              @core.undefined()
            }
          }),
          "disabled": @core.any(
            locked ||
            playing ||
            truthy(controller.editor._get("viewingPlayback")) ||
            timing.type_ is Cut,
          ),
          "disabledReason": if timing.type_ is Cut {
            @core.any(
              "Cut は瞬時に切り替わるため、イージングを使用しません。",
            )
          } else if playing {
            @core.any(
              "再生を停止すると、イージングを調整できます。",
            )
          } else {
            @core.undefined()
          },
        },
        [],
      ),
    ]),
  )
  content.push(
    component(
      property_timing_inspector,
      {
        "key": @core.any(key),
        "object": object,
        "transition": transition,
        "track": native,
      },
      [],
    ),
  )
  if timing.type_ is Move && from_visible && to_visible {
    let editing = truthy(controller.editor._get("pathEditing"))
    let path_fields : Array[&@react.ReactNode] = [
      inspector_button(
        if editing {
          "Finish editing path"
        } else {
          "Edit Bézier path"
        },
        "Spline",
        fn() {
          if timing.path is None {
            let from = @boundary.read_object_state(from)
            let to = @boundary.read_object_state(to)
            set_track(
              {
                "path": host_record({
                  "c1": host_record({
                    "x": @core.any(from.x + (to.x - from.x) / 3.0),
                    "y": @core.any(from.y),
                  }),
                  "c2": host_record({
                    "x": @core.any(from.x + (to.x - from.x) * 2.0 / 3.0),
                    "y": @core.any(to.y),
                  }),
                }),
              },
              true,
            )
          }
          controller.editor
          ._get("setPathEditing")
          ._invoke([@core.any(!editing)])
          |> ignore
        },
        class_name="subtle-button full-width " +
          (if editing { "active" } else { "" }),
      ),
    ]
    if timing.path is Some(_) {
      path_fields.push(
        inspector_button(
          "Use a straight path",
          "",
          fn() {
            set_track({ "path": @core.null() }, true)
            controller.editor._get("setPathEditing")._invoke([@core.any(false)])
            |> ignore
          },
          class_name="text-button",
        ),
      )
    }
    content.push(inspector_section("Motion path", path_fields))
  }
  let presence = if entering || leaving {
    let composition = scene
      ._get("compositions")
      ._get(if entering { to_id } else { from_id })
    (if truthy(composition) {
      string_value(composition._get("name"))
    } else {
      "undefined"
    }) +
    " only"
  } else {
    "Both compositions"
  }
  let presence_fields : Array[&@react.ReactNode] = [
    h("p", { "className": @core.any("muted small") }, [presence]),
  ]
  for
    (label, accessible, composition_id, visible) in [
      ("From", "Present in source composition", from_id, from_visible),
      ("To", "Present in destination composition", to_id, to_visible),
    ] {
    presence_fields.push(
      component(field, { "label": @core.any(label) }, [
        h(
          "select",
          {
            "aria-label": @core.any(accessible),
            "value": @core.any(if visible { "visible" } else { "none" }),
            "onChange": @core.any(fn(event : @core.Any) {
              if controller.can_edit() {
                let value : String = event._get("target")._get("value").cast()
                store._call("updateState", [
                  @core.any(controller.scene_id),
                  @core.any(composition_id),
                  @core.any(object_id),
                  host_record({ "visible": @core.any(value == "visible") }),
                ])
                |> ignore
              }
            }),
          },
          [export_choice("visible", "Visible"), export_choice("none", "None")],
        ),
      ]),
    )
  }
  content.push(inspector_section("Presence", presence_fields))
  content
}
