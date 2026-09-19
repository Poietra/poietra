///|
pub fn property_timing_inspector(input : @core.Any) -> @react.Element {
  let editor = use_editor()
  let scene = editor._get("scene")
  let store = editor._get("store")
  let object = input._get("object")
  let transition = input._get("transition")
  let track = @boundary.read_track(input._get("track"))
  let (chosen, set_chosen) = @react.use_state(@scene.PropertyChannel::Position)
  let channels = @editor.property_channels(
    @boundary.read_object_kind(object._get("kind")),
    track,
  )
  let channel = if channels.contains(chosen) { chosen } else { channels[0] }
  let channel_name = @editor.property_channel_name(channel)
  let timing = @scene.timing_override(track, channel).unwrap_or({
    start: track.start,
    duration: track.duration,
    easing: track.easing,
  })
  let independent = @scene.timing_override(track, channel) is Some(_)
  let object_id : String = object._get("id").cast()
  let transition_id : String = transition._get("id").cast()
  let scene_id : String = scene._get("id").cast()
  let visible = truthy(
    @boundary.visible_animation(scene, transition, object_id),
  )
  let label = @editor.property_channel_label(channel)
  let (error, set_error) = @react.use_state("")
  let playing = truthy(editor._get("playing"))
  let playback = truthy(editor._get("viewingPlayback"))
  let apply = fn(patch : @editor.PropertyTimingChange, separate : Bool) {
    if playing || playback {
      return
    }
    attempt(
      fn() {
        let current_scene = store._call("scene", [@core.any(scene_id)])
        let current_transition = current_scene
          ._get("transitions")
          ._get(transition_id)
        if !truthy(current_transition) {
          return
        }
        let current = @boundary.visible_animation(
          current_scene, current_transition, object_id,
        )
        if !truthy(current) || truthy(current._get("object")._get("locked")) {
          return
        }
        let previous = @boundary.read_timing(
          @boundary.get_property_timing(current._get("track"), channel_name),
        )
        let next = @editor.change_property_timing(
          previous,
          patch,
          current_transition._get("duration").cast(),
        )
        store._call("setPropertyTiming", [
          @core.any(scene_id),
          @core.any(transition_id),
          @core.any(object_id),
          @core.any(channel_name),
          next.map(@boundary.write_timing).unwrap_or(@core.null()),
          @core.any(separate),
        ])
        |> ignore
        set_error("")
      },
      set_error,
      "時間を変更できませんでした。",
    )
  }
  let options : Array[&@react.ReactNode] = []
  for value in channels {
    options.push(
      export_choice(
        @editor.property_channel_name(value),
        @editor.property_channel_label(value) +
        (if @scene.timing_override(track, value) is Some(_) {
          " · 個別"
        } else {
          ""
        }),
      ),
    )
  }
  let content : Array[&@react.ReactNode] = [
    component(field, { "label": @core.any("Property") }, [
      h(
        "select",
        {
          "aria-label": @core.any("Animation property"),
          "value": @core.any(channel_name),
          "onChange": @core.any(fn(event : @core.Any) {
            set_chosen(
              @scene.property_channel(event._get("target")._get("value").cast()).unwrap_or(
                Position,
              ),
            )
            set_error("")
          }),
        },
        options,
      ),
    ]),
    h(
      "p",
      { "className": @core.any("property-timing-note property-timing-mode") },
      [
        h("span", { "aria-hidden": @core.any(!independent) }, [
          "この項目だけ、個別の時間で変化します。",
        ]),
        h("span", { "aria-hidden": @core.any(independent) }, [
          "共通の Timing を使用中。下の値を変えると、この項目だけ時間を分けられます。",
        ]),
      ],
    ),
  ]
  let duration : Double = transition._get("duration").cast()
  let disabled = truthy(object._get("locked")) ||
    playing ||
    playback ||
    !visible
  content.push(
    h(
      "fieldset",
      {
        "className": @core.any("property-timing-fields"),
        "disabled": @core.any(disabled),
      },
      [
        component(field, { "label": @core.any("Start") }, [
          component(
            number_input,
            {
              "key": @core.any(channel_name + "/start"),
              "value": @core.any(timing.start),
              "label": @core.any(label + " animation start"),
              "suffix": @core.any("ms"),
              "min": @core.any(0),
              "max": @core.any(duration),
              "onChange": @core.any(fn(value : Double) {
                apply(@editor.TimingStart(value), true)
              }),
            },
            [],
          ),
        ]),
        component(field, { "label": @core.any("Duration") }, [
          component(
            number_input,
            {
              "key": @core.any(channel_name + "/duration"),
              "value": @core.any(timing.duration),
              "label": @core.any(label + " animation duration"),
              "suffix": @core.any("ms"),
              "min": @core.any(0),
              "max": @core.any((duration - timing.start).max(0.0)),
              "onChange": @core.any(fn(value : Double) {
                apply(@editor.TimingDuration(value), true)
              }),
            },
            [],
          ),
        ]),
        component(
          easing_editor,
          {
            "key": @core.any(
              "\{scene_id}/\{transition_id}/\{object_id}/\{channel_name}",
            ),
            "value": @boundary.write_easing(timing.easing),
            "label": @core.any(label + " animation easing"),
            "onChange": @core.any(fn(value : @core.Any, separate : @core.Any) {
              apply(
                @editor.TimingEasing(@boundary.read_easing(value)),
                @core.is_undefined(separate) || truthy(separate),
              )
            }),
            "getValue": @core.any(fn() {
              let current = store
                ._call("project", [])
                ._get("scenes")
                ._get(scene_id)
              if !truthy(current) {
                return @core.undefined()
              }
              let latest = current._get("transitions")._get(transition_id)
              if !truthy(latest) {
                return @core.undefined()
              }
              let animation = @boundary.visible_animation(
                current, latest, object_id,
              )
              if truthy(animation) {
                @boundary.get_property_timing(
                  animation._get("track"),
                  channel_name,
                )._get("easing")
              } else {
                @core.undefined()
              }
            }),
            "disabled": @core.any(disabled || track.type_ is Cut),
            "disabledReason": if track.type_ is Cut {
              @core.any(
                "Cut は瞬時に切り替わるため、イージングを使用しません。",
              )
            } else {
              @core.undefined()
            },
          },
          [],
        ),
        h(
          "button",
          {
            "className": @core.any(
              "subtle-button full-width property-timing-reset",
            ),
            "disabled": @core.any(!independent),
            "onClick": @core.any(fn() { apply(@editor.ResetTiming, true) }),
          },
          [icon("RotateCcw", 13), "共通の時間に戻す"],
        ),
      ],
    ),
  )
  if !visible {
    content.push(
      h("p", { "className": @core.any("property-timing-note") }, [
        "いずれかの Composition で表示すると、動きを調整できます。",
      ]),
    )
  }
  if channel is Reveal {
    content.push(
      h("p", { "className": @core.any("property-timing-note") }, [
        "Write の描画、Grow の拡大・縮小の進行を調整します。",
      ]),
    )
  }
  if channel is Position {
    content.push(
      h("p", { "className": @core.any("property-timing-note") }, [
        "X・Y と移動パスの進行を一緒に調整します。",
      ]),
    )
  }
  if !error.is_empty() {
    content.push(
      h(
        "p",
        {
          "className": @core.any("property-timing-error"),
          "role": @core.any("alert"),
        },
        [error],
      ),
    )
  }
  component(section, { "title": @core.any("Property timing") }, [
    h(
      "div",
      { "className": @core.any("property-animation-inspector") },
      content,
    ),
  ])
}
