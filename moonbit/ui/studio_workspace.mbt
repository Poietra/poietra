///|
let studio_media_accept : String = "video/mp4,video/webm,audio/mpeg,audio/wav,audio/ogg,audio/flac,audio/mp4,audio/webm,audio/x-wav,audio/x-flac,audio/x-m4a,.mp3,.wav,.ogg,.flac,.m4a,.mp4,.webm"

///|
fn studio_add_media(
  input : @react.ReactRef[@core.Any],
  kind : @core.Any,
) -> Unit {
  if input.get_current() is Some(input) {
    let accept = if @core.equal(kind, @core.any("audio")) {
      "audio/*,.mp3,.wav,.ogg,.flac,.m4a"
    } else if @core.equal(kind, @core.any("video")) {
      "video/mp4,video/webm,.mp4,.webm"
    } else {
      studio_media_accept
    }
    input._set("accept", @core.any(accept))
    input._call("click", []) |> ignore
  }
}

///|
fn studio_import_input(
  input : @react.ReactRef[@core.Any],
  label : String,
  accept : String,
  action : @core.Any,
) -> @react.Element {
  h(
    "input",
    {
      "key": @core.any(label),
      "ref": input.as_any(),
      "type": @core.any("file"),
      "aria-label": @core.any(label),
      "accept": @core.any(accept),
      "multiple": @core.any(true),
      "hidden": @core.any(true),
      "onChange": @core.any(fn(event : @core.Any) {
        let input = event._get("currentTarget")
        let files = @core.global_this()
          ._get("Array")
          ._call("from", [input._get("files")])
        input._set("value", @core.any(""))
        action._invoke([files]) |> ignore
      }),
    },
    [],
  )
}

///|
fn studio_workspace_heading(
  controller : StudioController,
  imports : @core.Any,
  image_input : @react.ReactRef[@core.Any],
  media_input : @react.ReactRef[@core.Any],
) -> @react.Element {
  let state = controller.state
  let doc = controller.document
  let compare = truthy(doc.transition) && !state.viewing()
  let crumbs : Array[&@react.ReactNode] = []
  if compare {
    crumbs.append([
      h("span", Map([]), [
        HostNode::{
          value: doc.scene
          ._get("compositions")
          ._get(doc.transition._get("fromId").cast())
          ._get("name"),
        },
      ]),
      icon("ArrowRight", 17),
      h("span", Map([]), [
        HostNode::{
          value: doc.scene
          ._get("compositions")
          ._get(doc.transition._get("toId").cast())
          ._get("name"),
        },
      ]),
    ])
  } else {
    crumbs.push(
      h("span", Map([]), [
        HostNode::{
          value: if state.viewing() {
            doc.scene._get("name")
          } else {
            doc.scene._get("compositions")._get(doc.composition)._get("name")
          },
        },
      ]),
    )
    crumbs.push(
      h("span", { "className": @core.any("muted workspace-subtitle") }, [
        if state.viewing() {
          "Preview"
        } else {
          "Composition"
        },
      ]),
    )
  }
  let busy = truthy(imports._get("importingImage")) ||
    truthy(imports._get("mediaImport")) ||
    state.viewing() ||
    state.playing()
  let actions : Array[&@react.ReactNode] = [
    h(
      "button",
      {
        "className": @core.any("subtle-button image-add-button"),
        "disabled": @core.any(busy),
        "onClick": @core.any(fn() {
          if image_input.get_current() is Some(input) {
            input._call("click", []) |> ignore
          }
        }),
      },
      [
        icon("ImagePlus", 14),
        if truthy(imports._get("importingImage")) {
          "Uploading…"
        } else {
          "Add image"
        },
      ],
    ),
    h(
      "button",
      {
        "className": @core.any("subtle-button"),
        "disabled": @core.any(busy),
        "onClick": @core.any(fn() {
          studio_add_media(media_input, @core.undefined())
        }),
      },
      [icon("Film", 14), "Add media"],
    ),
  ]
  actions.push(
    if compare {
      h(
        "button",
        {
          "className": @core.any(
            "subtle-button preview-button " +
            (if state.playing() { "active" } else { "" }),
          ),
          "onClick": @core.any(fn() { controller.play(SelectedTransition) }),
        },
        [
          icon(if state.playing() { "Pause" } else { "Play" }, 13, props={
            "fill": @core.any("currentColor"),
          }),
          "Preview",
        ],
      )
    } else {
      h("span", { "className": @core.any("workspace-dimensions") }, [
        string_value(doc.scene._get("width")) +
        " × " +
        string_value(doc.scene._get("height")),
      ])
    },
  )
  h(
    "div",
    { "key": @core.any("heading"), "className": @core.any("workspace-heading") },
    [
      studio_div("workspace-breadcrumb", crumbs),
      studio_div("workspace-actions", actions),
    ],
  )
}

///|
fn studio_import_status(imports : @core.Any) -> @react.Element {
  let progress = imports._get("mediaImport")
  let text = if truthy(progress) {
    let phase : String = progress._get("phase").cast()
    string_value(progress._get("index")) +
    "/" +
    string_value(progress._get("count")) +
    " · " +
    string_value(progress._get("name")) +
    " · " +
    (match phase {
      "waveform" => "波形を作成中"
      "uploading" => "アップロード中"
      "saving" => "共有素材を保存中"
      _ => "素材を読み込み中"
    })
  } else {
    "画像を準備・保存しています…"
  }
  let nodes : Array[&@react.ReactNode] = [
    icon("LoaderCircle", 16, props={ "className": @core.any("loading-spinner") }),
    h("span", Map([]), [text]),
  ]
  if truthy(progress) {
    nodes.push(
      h(
        "progress",
        {
          "max": @core.any(1),
          "value": progress._get("progress"),
          "aria-label": @core.any("素材の読み込み進捗"),
        },
        [],
      ),
    )
  }
  nodes.push(
    h(
      "button",
      {
        "className": @core.any("text-button"),
        "onClick": imports._get("cancel"),
      },
      ["中止"],
    ),
  )
  h(
    "div",
    {
      "key": @core.any("import-progress"),
      "className": @core.any("media-import-status"),
      "role": @core.any("status"),
      "aria-live": @core.any("polite"),
    },
    nodes,
  )
}

///|
fn studio_transition_stages(
  controller : StudioController,
  frames : StudioFrames,
  time : Double,
) -> Array[&@react.ReactNode] {
  let doc = controller.document
  let state = controller.state
  let from : String = doc.transition._get("fromId").cast()
  let to : String = doc.transition._get("toId").cast()
  let single = doc.objects.length() == 1
  let name = if single {
    string_value(doc.scene._get("objects")._get(doc.objects[0])._get("name"))
  } else {
    ""
  }
  let from_state = if single {
    doc.scene
    ._get("compositions")
    ._get(from)
    ._get("states")
    ._get(doc.objects[0])
  } else {
    @core.undefined()
  }
  let animation = if single {
    let track = doc.transition._get("tracks")._get(doc.objects[0])
    let text : String = if truthy(track) {
      track._get("type").cast()
    } else {
      "move"
    }
    if text.is_empty() {
      "Move"
    } else {
      text[:1].to_owned().to_upper() + text[1:].to_owned()
    }
  } else {
    "Composition"
  }
  [
    h(
      "div",
      { "key": @core.any("compare"), "className": @core.any("compare-stages") },
      [
        studio_div("compare-column", [
          studio_div("compare-label", [
            h("span", Map([]), ["From"]),
            HostNode::{
              value: doc.scene._get("compositions")._get(from)._get("name"),
            },
          ]),
          keyed_element(
            cached_stage,
            {
              "frame": frames.from,
              "compositionId": @core.any(from),
              "interactive": @core.any(false),
              "prefix": @core.any("from"),
            },
            [],
          ),
          studio_div("compare-caption", [
            if single {
              name
            } else {
              "Start state"
            },
            h("span", Map([]), [
              icon("ArrowRight", 12),
              if single &&
                (!truthy(from_state) || !truthy(from_state._get("visible"))) {
                "Enter"
              } else {
                "Transition"
              },
            ]),
          ]),
        ]),
        studio_div("compare-column", [
          studio_div("compare-label", [
            h("span", Map([]), ["To"]),
            HostNode::{
              value: doc.scene._get("compositions")._get(to)._get("name"),
            },
          ]),
          keyed_element(
            cached_stage,
            {
              "frame": if truthy(frames.transition) {
                frames.transition
              } else {
                frames.to
              },
              "compositionId": @core.any(to),
              "stateEditing": @core.any(!truthy(frames.transition)),
              "prefix": @core.any("to"),
            },
            [],
          ),
          studio_div("compare-caption", [
            if single {
              name
            } else {
              "End state"
            },
            h("span", Map([]), [animation]),
          ]),
        ]),
      ],
    ),
    h(
      "div",
      {
        "key": @core.any("transport"),
        "className": @core.any("preview-transport"),
      },
      [
        studio_icon_button(
          if state.playing() {
            "プレビューを停止"
          } else {
            "Transition をプレビュー"
          },
          if state.playing() {
            "Pause"
          } else {
            "Play"
          },
          14,
          fn() { controller.play(SelectedTransition) },
          icon_props={ "fill": @core.any("currentColor") },
        ),
        h("span", Map([]), [
          @boundary.format_milliseconds(doc.local_time(time)) +
          " / " +
          @boundary.format_milliseconds(doc.transition._get("duration").cast()) +
          " ms",
        ]),
        h(
          "input",
          {
            "aria-label": @core.any("Transition preview position"),
            "type": @core.any("range"),
            "min": @core.any(0),
            "max": doc.transition._get("duration"),
            "value": @core.any(doc.local_time(time)),
            "step": @core.any(1),
            "onChange": @core.any(fn(event : @core.Any) {
              let start = if truthy(controller.document.selected) {
                controller.document.selected._get("start").cast()
              } else {
                0.0
              }
              controller.seek(
                start + number_value(event._get("target")._get("value").cast()),
                SelectedTransition,
              )
            }),
          },
          [],
        ),
      ],
    ),
  ]
}

///|
fn studio_composition_stage(
  controller : StudioController,
  frames : StudioFrames,
) -> @react.Element {
  let state = controller.state
  let tools : Array[&@react.ReactNode] = []
  for
    (name, value, label) in [
      ("MousePointer2", "select", "選択 (V)"),
      ("Square", "rectangle", "四角形 (R)"),
      ("Circle", "circle", "円 (O)"),
      ("Spline", "path", "ベジェ曲線 (P)"),
      ("Sigma", "equation", "数式 (E)"),
      ("Type", "text", "テキスト (T)"),
      ("ArrowUpRight", "arrow", "矢印 (L)"),
      ("Minus", "numberline", "数直線"),
    ] {
    tools.push(
      studio_icon_button(
        label,
        name,
        18,
        fn() { controller.activate(studio_tool(value)) },
        extra={
          "key": @core.any(value),
          "active": @core.any(studio_tool_name(state.tool) == value),
        },
        icon_props={ "strokeWidth": @core.any(1.5) },
      ),
    )
  }
  tools.push(
    h(
      "div",
      { "key": @core.any("divider"), "className": @core.any("tool-divider") },
      [],
    ),
  )
  tools.push(
    studio_icon_button(
      "共同編集チャット",
      "MessageCircle",
      19,
      fn() {
        controller.update({
          ..controller.state,
          panel: if controller.state.panel == ChatPanel {
            DesignPanel
          } else {
            ChatPanel
          },
        })
      },
      extra={
        "key": @core.any("chat"),
        "active": @core.any(state.panel == ChatPanel),
      },
    ),
  )
  let nodes : Array[&@react.ReactNode] = [
    keyed_element(
      cached_stage,
      {
        "frame": frames.current,
        "compositionId": @core.any(controller.document.composition),
        "interactive": @core.any(!state.viewing()),
        "zoom": @core.any(state.zoom),
      },
      [],
    ),
    studio_div("floating-tools", tools),
  ]
  if !(state.tool is SelectTool) {
    nodes.push(
      studio_div("tool-instruction", [
        "キャンバスをクリック、またはドラッグして追加",
        h("span", Map([]), ["Esc でキャンセル"]),
      ]),
    )
  }
  h(
    "div",
    {
      "key": @core.any("main-stage"),
      "className": @core.any("main-stage-area"),
    },
    nodes,
  )
}

///|
fn studio_main(
  controller : StudioController,
  imports : @core.Any,
  image_input : @react.ReactRef[@core.Any],
  media_input : @react.ReactRef[@core.Any],
) -> @react.Element {
  let state = controller.state
  let doc = controller.document
  let workspace : Array[&@react.ReactNode] = [
    studio_workspace_heading(controller, imports, image_input, media_input),
  ]
  if truthy(imports._get("mediaImport")) ||
    truthy(imports._get("importingImage")) {
    workspace.push(studio_import_status(imports))
  }
  let error : String = imports._get("importError").cast()
  if !error.is_empty() {
    workspace.push(
      h(
        "div",
        {
          "key": @core.any("import-error"),
          "className": @core.any("media-import-status is-error"),
          "role": @core.any("alert"),
        },
        [
          h("span", Map([]), [error]),
          studio_icon_button("素材エラーを閉じる", "X", 14, fn() {
            imports._get("setImportError")._invoke([@core.any("")]) |> ignore
          }),
        ],
      ),
    )
  }
  if state.transport is Preparing(_, _) || !state.audio_error.is_empty() {
    let nodes : Array[&@react.ReactNode] = [
      h("span", Map([]), [
        if state.audio_error.is_empty() {
          "音声を準備しています…"
        } else {
          state.audio_error
        },
      ]),
    ]
    if !state.audio_error.is_empty() {
      nodes.push(
        studio_icon_button("音声エラーを閉じる", "X", 14, fn() {
          controller.update({ ..controller.state, audio_error: "", })
        }),
      )
    }
    workspace.push(
      h(
        "div",
        {
          "key": @core.any("audio-status"),
          "className": @core.any(
            if state.audio_error.is_empty() {
              "media-import-status"
            } else {
              "media-import-status is-error"
            },
          ),
          "role": @core.any(
            if state.audio_error.is_empty() {
              "status"
            } else {
              "alert"
            },
          ),
        },
        nodes,
      ),
    )
  }
  if !state.render_error.is_empty() {
    workspace.push(
      h(
        "div",
        {
          "key": @core.any("render-error"),
          "className": @core.any("render-error"),
          "role": @core.any("alert"),
        },
        [
          h("p", Map([]), [state.render_error]),
          h(
            "button",
            {
              "className": @core.any("subtle-button"),
              "onClick": @core.any(fn() {
                controller.update({
                  ..controller.state,
                  render_error: "",
                  render_attempt: controller.state.render_attempt + 1,
                })
              }),
            },
            [icon("RotateCcw", 14), "描画の準備を再試行"],
          ),
        ],
      ),
    )
  } else if state.render_revision == 0 {
    workspace.push(
      h(
        "div",
        {
          "key": @core.any("loading"),
          "className": @core.any("canvas-loading"),
        },
        [
          icon("LoaderCircle", 20, props={
            "className": @core.any("loading-spinner"),
          }),
        ],
      ),
    )
  } else {
    workspace.push(
      component(
        studio_stage_view,
        { "key": @core.any("stage"), "controller": @core.any(controller) },
        [],
      ),
    )
  }
  let nodes : Array[&@react.ReactNode] = []
  if state.image_drag {
    nodes.push(
      h(
        "div",
        {
          "key": @core.any("drop-hint"),
          "className": @core.any("media-drop-hint"),
        },
        [
          icon("Film", 30),
          h("strong", Map([]), ["ここに素材をドロップ"]),
          h("small", Map([]), [
            "画像・動画はキャンバスに、音声は専用トラックに追加",
          ]),
        ],
      ),
    )
  }
  nodes.append([
    studio_import_input(
      media_input,
      "音声・動画ファイル",
      studio_media_accept,
      imports._get("importMediaFiles"),
    ),
    studio_import_input(
      image_input,
      "画像ファイル",
      "image/png,image/jpeg,image/webp",
      imports._get("importImages"),
    ),
    h(
      "div",
      {
        "key": @core.any("workspace"),
        "className": @core.any(
          "workspace " +
          (if truthy(doc.transition) && !state.viewing() {
            "transition-workspace"
          } else {
            ""
          }),
        ),
      },
      workspace,
    ),
    component(
      timeline,
      {
        "key": @core.any("timeline"),
        "zoom": @core.any(state.zoom),
        "setZoom": @core.any(fn(value : Double) {
          controller.update({ ..controller.state, zoom: value, })
        }),
      },
      [
        component(
          media_timeline,
          {
            "key": @core.any(doc.scene_id),
            "onAdd": @core.any(fn(kind : @core.Any) {
              studio_add_media(media_input, kind)
            }),
            "disabled": @core.any(
              truthy(imports._get("importingImage")) ||
              truthy(imports._get("mediaImport")) ||
              state.viewing(),
            ),
          },
          [],
        ),
      ],
    ),
  ])
  h(
    "main",
    {
      "className": @core.any(
        "editor-main" +
        (if state.image_drag { " image-drop-active" } else { "" }),
      ),
      "onDragOver": @core.any(fn(event : @core.Any) {
        let types : FixedArray[String] = event
          ._get("dataTransfer")
          ._get("types")
          .cast()
        if types.iter().any(fn(value) { value == "Files" }) {
          prevent_default(event)
          event._get("dataTransfer")._set("dropEffect", @core.any("copy"))
          controller.update({ ..controller.state, image_drag: true, })
        }
      }),
      "onDragLeave": @core.any(fn(event : @core.Any) {
        if !truthy(
            event
            ._get("currentTarget")
            ._call("contains", [event._get("relatedTarget")]),
          ) {
          controller.update({ ..controller.state, image_drag: false, })
        }
      }),
      "onDrop": @core.any(fn(event : @core.Any) {
        let files : FixedArray[@core.Any] = @core.global_this()
          ._get("Array")
          ._call("from", [event._get("dataTransfer")._get("files")])
          .cast()
        if files.is_empty() {
          return
        }
        prevent_default(event)
        controller.update({ ..controller.state, image_drag: false, })
        let surface = closest_element(event._get("target"), ".stage-surface")
        if truthy(surface) &&
          @core.equal(
            surface._get("dataset")._get("testid"),
            @core.any("stage-from"),
          ) {
          controller.notify(
            "右側の場面に素材をドロップしてください。",
          )
          return
        }
        let point = if truthy(surface) {
          let rect = stage_bounds(surface._call("getBoundingClientRect", []))
          let x : Double = event._get("clientX").cast()
          let y : Double = event._get("clientY").cast()
          stage_point({
            x: (x - rect.x) /
            rect.width *
            (doc.scene._get("width").cast() : Double),
            y: (y - rect.y) /
            rect.height *
            (doc.scene._get("height").cast() : Double),
          })
        } else {
          @core.undefined()
        }
        imports._get("importFiles")._invoke([@core.any(files), point]) |> ignore
      }),
    },
    nodes,
  )
}
