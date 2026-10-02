///|
let property_timing_component : TypedComponent[PropertyTimingView] = memo_typed_component(
  render_property_timing,
)

///|
fn render_property_timing(input : PropertyTimingView) -> @react.Element {
  let editor = use_editor_state()
  let animation = input.animation
  let binding = input.binding
  let track = animation.track
  let (chosen, set_chosen) = @react.use_state(@scene.PropertyChannel::Position)
  let channels = @editor.property_channels(animation.kind, track)
  let channel = if channels.contains(chosen) { chosen } else { channels[0] }
  let channel_name = @editor.property_channel_name(channel)
  let timing = animation.timing(channel)
  let independent = @scene.timing_override(track, channel) is Some(_)
  let visible = animation.visible
  let label = @editor.property_channel_label(channel)
  let (error, set_error) = @react.use_state("")
  let playing = editor.playing
  let playback = editor.viewing_playback
  let apply = fn(patch : @editor.PropertyTimingChange, separate : Bool) {
    if playing || playback {
      return
    }
    attempt(
      fn() {
        binding.change_timing(channel, patch, separate)
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
  let duration = animation.duration
  let disabled = animation.locked || playing || playback || !visible
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
        typed_component(
          easing_component,
          {
            value: Some(timing.easing),
            label: label + " animation easing",
            on_change: fn(value, separate) {
              apply(@editor.TimingEasing(value), separate)
            },
            current: Some(fn() {
              binding
              .property_timing(channel)
              .map(fn(current) { current.timing.easing })
            }),
            disabled: disabled || track.type_ is Cut,
            disabled_reason: if track.type_ is Cut {
              Some(
                "Cut は瞬時に切り替わるため、イージングを使用しません。",
              )
            } else {
              None
            },
          },
          key=binding.target.key() + "/" + channel_name,
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
  content.push(
    typed_component(
      keyframe_component,
      { animation, binding, evaluation: input.evaluation, channel, disabled, },
      key=binding.target.key(),
    ),
  )
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
