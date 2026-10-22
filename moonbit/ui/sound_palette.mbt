///|
let cached_sound_palette : TypedComponent[SoundPaletteView] = memo_typed_component(
  sound_palette,
)

///|
fn sound_palette(input : SoundPaletteView) -> @react.Element {
  let editor = input.editor
  let time = use_editor_position(editor)
  let presets = @sound_effects.presets()
  let (query, set_query) = @react.use_state("")
  let (settings, set_settings) = @react.use_state(SoundSettings::{
    preset: 0,
    duration: presets[0].duration,
    pitch: 0.0,
    volume: 80.0,
    seed: 1,
    target: MotionMiddle,
    sync: presets[0].sync,
    channel: None,
  })
  let (status, set_status) = @react.use_state(SoundStatus::Quiet)
  let (error, set_error) = @react.use_state("")
  let session : SoundSession = @react.use_memo(
    fn() {
      {
        editor,
        mounted: true,
        generation: 0,
        request: None,
        context: None,
        source: None,
        cached: None,
        status: set_status,
        error: set_error,
        added: input.added,
      }
    },
    [editor.store, editor.scene._get("id"), @core.any(editor.selection.id())],
  )
  session.editor = editor
  @react.use_effect(
    fn() {
      session.mounted = true
      set_status(Quiet)
      set_error("")
      let window = @core.global_this()._get("window")
      let document = @core.global_this()._get("document")
      let cancel = fn() { session.cancel() }
      let hidden = fn() {
        if truthy(document._get("hidden")) {
          session.cancel()
        }
      }
      window._call("addEventListener", [
        @core.any("pagehide"),
        @core.any(cancel),
      ])
      |> ignore
      document._call("addEventListener", [
        @core.any("visibilitychange"),
        @core.any(hidden),
      ])
      |> ignore
      fn() {
        window._call("removeEventListener", [
          @core.any("pagehide"),
          @core.any(cancel),
        ])
        |> ignore
        document._call("removeEventListener", [
          @core.any("visibilitychange"),
          @core.any(hidden),
        ])
        |> ignore
        session.dispose()
      }
    },
    [@core.any(session)],
  )
  @react.use_effect(
    fn() {
      if editor.playing || editor.viewing_playback {
        session.cancel()
      }
      fn() { () }
    },
    [@core.any(editor.playing), @core.any(editor.viewing_playback)],
  )
  let busy = status is Storing(_)
  let blocked = busy || editor.playing || editor.viewing_playback
  let change = fn(next : SoundSettings) {
    session.stop_preview()
    set_status(Quiet)
    set_error("")
    set_settings(next)
  }
  let choose = fn(index : Int) {
    if index != settings.preset {
      change({
        ..settings,
        preset: index,
        duration: presets[index].duration,
        sync: presets[index].sync,
        target: if presets[index].sync is @sound_effects.End &&
          settings.target is MotionStart {
          MotionEnd
        } else {
          settings.target
        },
      })
    }
  }
  let options : Array[&@react.ReactNode] = []
  let needle = @editor.trim_text(query).to_owned().to_lower()
  for index, preset in presets {
    if !(preset.name + preset.description + preset.keywords)
      .to_lower()
      .contains(needle) {
      continue
    }
    options.push(
      h(
        "div",
        { "key": @core.any(preset.id), "className": @core.any("sound-option") },
        [
          h(
            "button",
            {
              "className": @core.any("sound-choice"),
              "type": @core.any("button"),
              "aria-label": @core.any(preset.name),
              "aria-pressed": @core.any(index == settings.preset),
              "disabled": @core.any(blocked),
              "onClick": @core.any(fn() { choose(index) }),
            },
            [
              h("strong", Map([]), [preset.name]),
              h("span", Map([]), [preset.description]),
            ],
          ),
          h(
            "button",
            {
              "className": @core.any("icon-button"),
              "type": @core.any("button"),
              "aria-label": @core.any(preset.name + " を試聴"),
              "title": @core.any(preset.name + " を試聴"),
              "disabled": @core.any(blocked),
              "onClick": @core.any(fn() {
                choose(index)
                let next = if index == settings.preset {
                  settings
                } else {
                  {
                    ..settings,
                    preset: index,
                    duration: preset.duration,
                    sync: preset.sync,
                    target: if preset.sync is @sound_effects.End &&
                      settings.target is MotionStart {
                      MotionEnd
                    } else {
                      settings.target
                    },
                  }
                }
                session.preview(next, time) |> ignore
              }),
            },
            [icon("Play", 15)],
          ),
        ],
      ),
    )
  }
  if options.is_empty() {
    options.push(
      h("p", { "className": @core.any("muted") }, [
        "該当する効果音がありません。移動・出現・通知などで検索できます。",
      ]),
    )
  }
  let preset = presets[settings.preset]
  let range = sound_range(editor, settings.channel)
  let target = sound_target_time(settings, range, time)
  let is_transition = editor.selection is TransitionSelection(_)
  let target_name = if is_transition {
    if editor.selected_ids.is_empty() {
      "Transition"
    } else {
      settings.channel
      .map(fn(channel) {
        @editor.property_channel_label(channel) + " の動き"
      })
      .unwrap_or("選択オブジェクトの動き")
    }
  } else {
    "場面"
  }
  let controls : Array[&@react.ReactNode] = [
    h("div", { "className": @core.any("sound-knobs") }, [
      number_field(
        "長さ",
        "効果音の長さ",
        settings.duration,
        fn(value) { change({ ..settings, duration: value, }) },
        min=60.0,
        max=3000.0,
        suffix="ms",
      ),
      number_field(
        "高さ",
        "効果音の高さ",
        settings.pitch,
        fn(value) { change({ ..settings, pitch: value, }) },
        min=-12.0,
        max=12.0,
        suffix="半音",
      ),
      number_field(
        "音量",
        "効果音の音量",
        settings.volume,
        fn(value) { change({ ..settings, volume: value, }) },
        min=0.0,
        max=100.0,
        suffix="%",
      ),
    ]),
    h("div", { "className": @core.any("sound-placement") }, [
      h("label", Map([]), [
        "合わせる位置",
        select_input(
          "効果音を合わせる位置",
          match settings.target {
            MotionStart => "start"
            MotionMiddle => "middle"
            MotionEnd => "end"
            CurrentPosition => "playhead"
          },
          fn(value) {
            change({
              ..settings,
              target: match value {
                "start" => MotionStart
                "middle" => MotionMiddle
                "end" => MotionEnd
                _ => CurrentPosition
              },
            })
          },
          [
            select_choice("start", target_name + "の開始"),
            select_choice("middle", target_name + "の中央"),
            select_choice("end", target_name + "の終了"),
            select_choice("playhead", "再生ヘッド"),
          ],
          disabled=blocked,
        ),
      ]),
      h("label", Map([]), [
        "音の同期点",
        select_input(
          "効果音の同期点",
          match settings.sync {
            @sound_effects.Onset => "onset"
            Peak => "peak"
            End => "end"
          },
          fn(value) {
            change({
              ..settings,
              sync: match value {
                "peak" => @sound_effects.Peak
                "end" => End
                _ => Onset
              },
            })
          },
          [
            select_choice("onset", "鳴り始め"),
            select_choice("peak", "ピーク"),
            select_choice("end", "余韻の終わり"),
          ],
          disabled=blocked,
        ),
      ]),
    ]),
  ]
  if is_transition && !editor.selected_ids.is_empty() {
    let channels = [select_choice("all", "動きの全体")]
    for channel in @scene.property_channels() {
      channels.push(
        select_choice(
          @editor.property_channel_name(channel),
          @editor.property_channel_label(channel),
        ),
      )
    }
    controls.insert(
      1,
      h("label", { "className": @core.any("sound-channel") }, [
        "合わせる動きの属性",
        select_input(
          "効果音を合わせる属性",
          settings.channel.map(@editor.property_channel_name).unwrap_or("all"),
          fn(value) {
            change({ ..settings, channel: @scene.property_channel(value), })
          },
          channels,
          disabled=blocked || settings.target is CurrentPosition,
        ),
      ]),
    )
  }
  let nodes : Array[&@react.ReactNode] = [
    h(
      "input",
      {
        "className": @core.any("content-input"),
        "type": @core.any("search"),
        "aria-label": @core.any("効果音を検索"),
        "placeholder": @core.any("移動、出現、着地、通知…"),
        "value": @core.any(query),
        "disabled": @core.any(blocked),
        "onChange": @core.any(fn(event : @core.Any) {
          set_query(event._get("target")._get("value").cast())
        }),
      },
      [],
    ),
    h("div", { "className": @core.any("sound-options") }, options),
    h(
      "fieldset",
      {
        "disabled": @core.any(blocked),
        "className": @core.any("sound-settings"),
      },
      [h("legend", Map([]), [preset.name]), h("div", Map([]), controls)],
    ),
    h(
      "p",
      {
        "className": @core.any("sound-cue-note"),
        "data-testid": @core.any("sound-cue"),
      },
      [
        "Scene ",
        fixed_number(target / 1000.0, 3),
        " s に音の",
        match settings.sync {
          @sound_effects.Onset => "鳴り始め"
          Peak => "ピーク"
          End => "余韻の終わり"
        },
        "を合わせます。Scene 開始より前の部分はカットされます。",
      ],
    ),
  ]
  if !error.is_empty() {
    nodes.push(
      h(
        "p",
        { "className": @core.any("sound-error"), "role": @core.any("alert") },
        [error],
      ),
    )
  }
  if status is Storing(progress) {
    nodes.push(
      h(
        "div",
        {
          "className": @core.any("sound-progress"),
          "role": @core.any("status"),
        },
        [
          "効果音を保存中…",
          h(
            "progress",
            {
              "aria-label": @core.any("効果音の保存進捗"),
              "max": @core.any(1),
              "value": @core.any(progress),
            },
            [],
          ),
          inspector_button(
            "追加を中止",
            "X",
            fn() { session.cancel() },
            class_name="text-button",
          ),
        ],
      ),
    )
  }
  nodes.push(
    h("div", { "className": @core.any("sound-actions") }, [
      inspector_button(
        if status is Listening {
          "試聴を停止"
        } else {
          "試聴"
        },
        if status is Listening {
          "Square"
        } else {
          "Play"
        },
        fn() {
          if status is Listening {
            session.stop_preview()
            set_status(Quiet)
          } else {
            session.preview(settings, time) |> ignore
          }
        },
        class_name="subtle-button",
        disabled=blocked,
      ),
      inspector_button(
        "別の響き",
        "RefreshCw",
        fn() { change({ ..settings, seed: settings.seed + 1, }) },
        class_name="text-button",
        disabled=blocked,
      ),
      inspector_button(
        "タイムラインに追加",
        "Plus",
        fn() { session.insert(settings, time) |> ignore },
        class_name="primary-button",
        disabled=blocked,
      ),
    ]),
  )
  component(
    modal,
    {
      "open": @core.any(true),
      "title": @core.any("効果音を追加"),
      "className": @core.any("sound-dialog"),
      "description": @core.any(
        "音を選んで試聴し、動きに合わせて追加します。素材ファイルの用意は不要です。",
      ),
      "onOpenChange": @core.any(fn(value : Bool) {
        if !value {
          session.dispose()
          (input.close)()
        }
      }),
    },
    [h("div", { "className": @core.any("sound-palette") }, nodes)],
  )
}
