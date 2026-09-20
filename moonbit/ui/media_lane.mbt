///|
fn media_lane(
  controller : MediaController,
  clip : MediaClip,
  timing : @scene.MediaPlayback,
  chosen : Bool,
  total : Double,
) -> @react.Element {
  let kind = if clip.kind is AudioClip { "audio" } else { "video" }
  let label = if clip.kind is AudioClip { "音声" } else { "動画" }
  let muted = clip.audio
    .map(fn(audio) { truthy(audio._get("muted")) })
    .unwrap_or(false)
  let heading : Array[&@react.ReactNode] = [
    h(
      "button",
      {
        "className": @core.any("media-select"),
        "aria-pressed": @core.any(chosen),
        "onClick": @core.any(fn() { controller.choose(clip) }),
        "title": @core.any(clip.name),
      },
      [
        icon(if clip.kind is AudioClip { "Music2" } else { "Film" }, 13),
        h("span", Map([]), [clip.name]),
      ],
    ),
  ]
  if clip.audio is Some(_) {
    heading.push(
      component(
        icon_button,
        {
          "label": @core.any(
            clip.name +
            (if muted {
              " のミュートを解除"
            } else {
              " をミュート"
            }),
          ),
          "active": @core.any(muted),
          "disabled": @core.any(controller.busy),
          "onClick": @core.any(fn() {
            let tracks = controller.store
              ._call("scene", [@core.any(controller.scene_id)])
              ._get("audioTracks")
            let current = if truthy(tracks) {
              tracks._get(clip.id)
            } else {
              @core.undefined()
            }
            controller.store._call("setAudioTrack", [
              @core.any(controller.scene_id),
              @core.any(clip.id),
              host_record({
                "muted": @core.any(
                  !(truthy(current) && truthy(current._get("muted"))),
                ),
              }),
            ])
            |> ignore
          }),
        },
        [icon(if muted { "VolumeX" } else { "Volume2" }, 13)],
      ),
    )
  }
  let dragging = controller.drag
    .map(fn(gesture) { gesture.clip.id == clip.id })
    .unwrap_or(false)
  let content : Array[&@react.ReactNode] = [
    if clip.kind is AudioClip {
      media_waveform(clip.asset, timing)
    } else {
      component(
        media_thumbnail,
        { "src": clip.asset._get("src"), "offset": @core.any(timing.offset) },
        [],
      )
    },
  ]
  content.push(
    h("span", { "className": @core.any("media-clip-name") }, [clip.name]),
  )
  content.push(
    h(
      "span",
      {
        "data-edge": @core.any("start"),
        "className": @core.any("media-clip-edge start"),
      },
      [],
    ),
  )
  content.push(
    h(
      "span",
      {
        "data-edge": @core.any("end"),
        "className": @core.any("media-clip-edge end"),
      },
      [],
    ),
  )
  let left = @scene.clamp(timing.start / total, 0.0, 1.0) * 100.0
  let width = @scene.maximum(
    0.0,
    @scene.minimum(
      100.0 - timing.start / total * 100.0,
      timing.duration / total * 100.0,
    ),
  )
  let bar = h(
    "button",
    {
      "className": classes([
        @core.any("media-clip"),
        @core.any(kind),
        @core.any(if clip.locked { "is-locked" } else { "" }),
        @core.any(if dragging { "is-dragging" } else { "" }),
      ]),
      "style": host_record({
        "left": @core.any(
          "min(" + string_value(@core.any(left)) + "%, calc(100% - 8px))",
        ),
        "width": @core.any(string_value(@core.any(width)) + "%"),
      }),
      "aria-label": @core.any(label + "クリップ " + clip.name),
      "aria-pressed": @core.any(chosen),
      "aria-disabled": @core.any(controller.busy || clip.locked),
      "aria-description": @core.any(
        if clip.locked {
          "ロック中 · 選択のみ"
        } else if controller.busy {
          "再生や素材の読み込みを停止すると編集できます"
        } else {
          "ドラッグで移動、両端でトリミング。選択して数値でも編集できます"
        },
      ),
      "title": @core.any(
        clip.name +
        " · " +
        media_seconds(timing.start) +
        "–" +
        media_seconds(timing.start + timing.duration) +
        (if clip.locked {
          " · ロック中"
        } else {
          " · ドラッグで移動、両端でトリミング"
        }),
      ),
      "onClick": @core.any(fn(event : @core.Any) {
        if event._get("detail").cast() == 0 {
          controller.choose(clip)
        }
      }),
      "onPointerDown": @core.any(fn(event : @core.Any) {
        controller.down(event, clip)
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
    },
    content,
  )
  h(
    "div",
    {
      "className": classes([
        @core.any("media-track-row"),
        @core.any(if chosen { "is-selected" } else { "" }),
        @core.any(if muted { "is-muted" } else { "" }),
      ]),
      "key": @core.any(clip.id),
      "data-testid": @core.any(kind + "-track"),
    },
    [
      h("div", { "className": @core.any("media-track-label") }, heading),
      h("div", { "className": @core.any("media-track-lane") }, [
        bar,
        component(media_playhead, { "total": @core.any(total) }, []),
      ]),
    ],
  )
}

///|
fn media_properties(
  controller : MediaController,
  clip : MediaClip,
) -> @react.Element {
  let duration : Double = clip.asset._get("duration").cast()
  let content : Array[&@react.ReactNode] = [
    h("label", Map([]), [
      "名前",
      h(
        "input",
        {
          "aria-label": @core.any("素材トラック名"),
          "value": @core.any(clip.name),
          "onChange": @core.any(fn(event : @core.Any) {
            let name : String = event._get("target")._get("value").cast()
            controller.store._call(
              if clip.kind is AudioClip {
                "setAudioTrack"
              } else {
                "setObject"
              },
              [
                @core.any(controller.scene_id),
                @core.any(clip.id),
                host_record({
                  "name": @core.any(name[:name.length().min(200)].to_owned()),
                }),
              ],
            )
            |> ignore
          }),
        },
        [],
      ),
    ]),
  ]
  let control = fn(
    label : String,
    accessible : String,
    value : Double,
    minimum : Double,
    maximum : Double,
    suffix : String,
    commit : (Double) -> Unit,
  ) {
    h("label", Map([]), [
      label,
      component(
        number_input,
        {
          "label": @core.any(accessible),
          "value": @core.any(value),
          "min": @core.any(minimum),
          "max": @core.any(maximum),
          "suffix": @core.any(suffix),
          "onChange": @core.any(commit),
        },
        [],
      ),
    ])
  }
  content.push(
    control(
      "開始",
      "素材の開始位置",
      clip.timing.start,
      0.0,
      600000.0,
      "ms",
      fn(value) {
        controller.update(clip, host_record({ "start": @core.any(value) }))
      },
    ),
  )
  content.push(
    control(
      "素材の先頭",
      "素材のトリム開始",
      clip.timing.offset,
      0.0,
      (duration - 10.0).max(0.0),
      "ms",
      fn(value) {
        controller.update(
          clip,
          host_record({
            "offset": @core.any(value),
            "duration": @core.any(clip.timing.duration.min(duration - value)),
          }),
        )
      },
    ),
  )
  content.push(
    control(
      "長さ",
      "素材の再生時間",
      clip.timing.duration,
      (duration - clip.timing.offset).min(10.0),
      duration - clip.timing.offset,
      "ms",
      fn(value) {
        controller.update(clip, host_record({ "duration": @core.any(value) }))
      },
    ),
  )
  if clip.audio is Some(audio) {
    let volume : Double = audio._get("volume").cast()
    content.push(
      control("音量", "音量", volume * 100.0, 0.0, 100.0, "%", fn(value) {
        controller.store._call("setAudioTrack", [
          @core.any(controller.scene_id),
          @core.any(clip.id),
          host_record({ "volume": @core.any(value / 100.0) }),
        ])
        |> ignore
      }),
    )
    content.push(
      component(
        icon_button,
        {
          "label": @core.any("音声トラックを削除"),
          "onClick": @core.any(fn() {
            controller.store._call("removeAudioTrack", [
              @core.any(controller.scene_id),
              @core.any(clip.id),
            ])
            |> ignore
            (controller.select)(None)
            (controller.notify)(
              "音声トラックを削除しました。Undo で戻せます。",
            )
          }),
        },
        [icon("Trash2", 14)],
      ),
    )
  }
  h(
    "fieldset",
    {
      "className": @core.any("media-clip-properties"),
      "disabled": @core.any(controller.busy || clip.locked),
    },
    content,
  )
}

///|
fn media_playhead(input : @core.Any) -> @react.Element {
  let total : Double = input._get("total").cast()
  let playhead = use_editor_position(use_editor_state())
  h(
    "i",
    {
      "className": @core.any("media-playhead"),
      "style": host_record({
        "left": @core.any(
          string_value(@core.any((playhead / total).min(1.0) * 100.0)) + "%",
        ),
      }),
    },
    [],
  )
}
