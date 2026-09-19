///|
fn scene_count(project : @core.Any) -> Int {
  let order : FixedArray[String] = project._get("sceneOrder").cast()
  order.length()
}

///|
fn export_choice(
  value : String,
  label : String,
  disabled? : Bool = false,
) -> @react.Element {
  h(
    "option",
    {
      "key": @core.any(value),
      "value": @core.any(value),
      "disabled": @core.any(disabled),
    },
    [label],
  )
}

///|
fn export_select(
  label : String,
  accessible : String,
  value : @core.Any,
  on_change : (String) -> Unit,
  options : Array[&@react.ReactNode],
) -> @react.Element {
  h("label", Map([]), [
    label,
    h(
      "select",
      {
        "aria-label": @core.any(accessible),
        "value": value,
        "onChange": @core.any(fn(event : @core.Any) {
          on_change(event._get("target")._get("value").cast())
        }),
      },
      options,
    ),
  ])
}

///|
pub fn export_dialog(input : @core.Any) -> @react.Element {
  let open : Bool = input._get("open").cast()
  let exporter = input._get("exporter")
  let scene = input._get("scene")
  let project = input._get("project")
  let (capabilities, set_capabilities) = @react.use_state(
    (None : ExportCapabilities?),
  )
  let (format, set_format) = @react.use_state(@exporting.Container::Mp4)
  let (fps, set_fps) = @react.use_state(30.0)
  let (resolution, set_resolution) = @react.use_state(ExportResolution::Source)
  let (range, set_range) = @react.use_state(ExportRange::CurrentScene)
  let (view, set_view) = @react.use_state(ExportView::Checking)
  let session = @react.use_ref((None : ExportSession?))
  let job = @react.use_ref((None : ExportJob?))
  let current = @react.use_ref(Some(input))
  current.set_current(Some(input))
  let can_project = truthy(project) && truthy(exporter._get("exportProject"))
  @react.use_effect(
    fn() {
      if !open {
        return fn() { () }
      }
      let token : ExportSession = { active: Ref(true), }
      session.set_current(Some(token))
      let active = fn() {
        token.active.val &&
        session
        .get_current()
        .map(fn(value) { @core.equal(@core.any(token), @core.any(value)) })
        .unwrap_or(false) &&
        truthy(current.get_current().unwrap()._get("open")) &&
        @core.equal(current.get_current().unwrap()._get("exporter"), exporter)
      }
      set_range(
        if can_project && scene_count(project) > 1 {
          EntireProject
        } else {
          CurrentScene
        },
      )
      set_capabilities(None)
      set_view(Checking)
      @core.from_async(async fn() {
        try {
          let value = ui_call(exporter, "getExportCapabilities", [])
          if !active() {
            return
          }
          let reason = value._get("reason")
          let caps : ExportCapabilities = {
            mp4: value._get("mp4").cast(),
            webm: value._get("webm").cast(),
            reason: if truthy(reason) {
              reason.cast()
            } else {
              ""
            },
          }
          set_capabilities(Some(caps))
          set_format(
            if caps.supports(format) {
              format
            } else if caps.mp4 {
              Mp4
            } else {
              Webm
            },
          )
          set_view(Ready)
        } catch {
          error =>
            if active() {
              set_view(
                Failed(
                  error_message(
                    ui_native_error(error),
                    "書き出しへの対応を確認できませんでした。画面を開き直してください。",
                  ),
                ),
              )
            }
        }
      })
      |> ignore
      fn() {
        token.active.val = false
        if job.get_current() is Some(active) &&
          @core.equal(@core.any(active.session), @core.any(token)) {
          job.set_current(None)
          active.controller._call("abort", []) |> ignore
        }
      }
    },
    [@core.any(open), exporter],
  )
  let change_open = fn(next : Bool) {
    if !next {
      if session.get_current() is Some(token) {
        token.active.val = false
      }
      if job.get_current() is Some(active) {
        job.set_current(None)
        active.controller._call("abort", []) |> ignore
      }
    }
    input._get("onOpenChange")._invoke([@core.any(next)]) |> ignore
  }
  let cancel = fn() {
    if job.get_current() is Some(active) {
      job.set_current(None)
      active.controller._call("abort", []) |> ignore
      set_view(Canceled)
    }
  }
  let render = fn() {
    if open &&
      session.get_current() is Some(token) &&
      token.active.val &&
      job.get_current() is None &&
      capabilities.map(fn(value) { value.supports(format) }).unwrap_or(false) {
      begin_export(
        input, format, fps, resolution, range, token, job, current, set_view,
      )
    }
  }
  let busy = view is Running(_, _)
  let completed = view is Completed(_, _)
  let frozen = view.frozen()
  let selected = selected_export_project(input, range)
  let displayed_project = frozen
    .map(fn(value) { value.project })
    .unwrap_or(selected)
  let displayed = frozen
    .map(fn(value) { value.scene })
    .unwrap_or_else(fn() { first_export_scene(selected, scene) })
  let duration = if truthy(displayed_project) {
    @boundary.project_duration(displayed_project)
  } else {
    @boundary.scene_duration(displayed)
  }
  let displayed_format = frozen
    .map(fn(value) { value.format })
    .unwrap_or(format)
  let displayed_fps = frozen.map(fn(value) { value.fps }).unwrap_or(fps)
  let title = if truthy(displayed_project) {
    string_value(displayed_project._get("name")) +
    " · \{scene_count(displayed_project)} scenes"
  } else {
    string_value(displayed._get("name"))
  }
  let settings : Array[&@react.ReactNode] = []
  if can_project {
    settings.push(
      export_select(
        "Range",
        "Export range",
        @core.any(if range == EntireProject { "project" } else { "scene" }),
        fn(value) {
          set_range(
            if value == "project" {
              EntireProject
            } else {
              CurrentScene
            },
          )
        },
        [
          export_choice(
            "project",
            "Entire project · \{scene_count(project)} scenes",
          ),
          export_choice(
            "scene",
            "Current scene · " + string_value(scene._get("name")),
          ),
        ],
      ),
    )
  }
  settings.push(
    export_select(
      "Format",
      "Export format",
      @core.any(displayed_format.extension()),
      fn(value) { set_format(if value == "mp4" { Mp4 } else { Webm }) },
      [
        export_choice(
          "mp4",
          "MP4",
          disabled=!capabilities.map(fn(value) { value.mp4 }).unwrap_or(false),
        ),
        export_choice(
          "webm",
          "WebM",
          disabled=!capabilities.map(fn(value) { value.webm }).unwrap_or(false),
        ),
      ],
    ),
  )
  let resolutions : Array[&@react.ReactNode] = []
  for choice in [ExportResolution::Source, HD, FullHD] {
    let size = export_dimensions(displayed, choice, displayed_format)
    let label = if choice == Source { "Source" } else { choice.value() + "p" }
    resolutions.push(
      export_choice(
        choice.value(),
        label + " · \{size.width} × \{size.height}",
      ),
    )
  }
  settings.push(
    export_select(
      "Resolution",
      "Export resolution",
      @core.any(resolution.value()),
      fn(value) {
        set_resolution(
          match value {
            "720" => HD
            "1080" => FullHD
            _ => Source
          },
        )
      },
      resolutions,
    ),
  )
  settings.push(
    export_select(
      "Frame rate",
      "Export frame rate",
      @core.any(displayed_fps),
      fn(value) { set_fps(number_value(value)) },
      [
        export_choice("24", "24 fps"),
        export_choice("30", "30 fps"),
        export_choice("60", "60 fps"),
      ],
    ),
  )
  let content : Array[&@react.ReactNode] = [
    h(
      "fieldset",
      {
        "className": @core.any("export-dialog-settings"),
        "disabled": @core.any(busy || completed || view is Checking),
      },
      settings,
    ),
  ]
  if truthy(displayed_project) {
    content.push(
      h("p", { "className": @core.any("export-dialog-note") }, [
        "Scene の順番で一本の動画にします。出力の比率は最初の Scene に合わせ、異なる比率の Scene は余白を付けて表示します。",
      ]),
    )
  }
  let source_width : Double = displayed._get("width").cast()
  let source_height : Double = displayed._get("height").cast()
  if resolution == Source &&
    displayed_format == Mp4 &&
    (source_width % 2.0 != 0.0 || source_height % 2.0 != 0.0) {
    content.push(
      h("p", { "className": @core.any("export-dialog-note") }, [
        "MP4 に合わせて、幅と高さを偶数ピクセルに調整します。",
      ]),
    )
  }
  if capabilities is Some(caps) && !caps.mp4 && !caps.webm {
    content.push(
      h(
        "p",
        { "className": @core.any("inline-error"), "role": @core.any("alert") },
        [
          if caps.reason.is_empty() {
            "このブラウザでは動画を書き出せません。WebCodecs 対応の Chrome または Edge で開いてください。"
          } else {
            caps.reason
          },
        ],
      ),
    )
  }
  if !view.error().is_empty() {
    content.push(
      h(
        "p",
        { "className": @core.any("inline-error"), "role": @core.any("alert") },
        [view.error()],
      ),
    )
  }
  let status : Array[&@react.ReactNode] = []
  if !view.message().is_empty() {
    let line : Array[&@react.ReactNode] = []
    if view is Checking || busy {
      line.push(
        icon("LoaderCircle", 14, props={
          "className": @core.any("loading-spinner"),
        }),
      )
    }
    line.push(view.message())
    status.push(h("p", Map([]), line))
  }
  if view is Running(_, progress) {
    status.push(
      h("div", { "className": @core.any("export-dialog-progress") }, [
        h(
          "progress",
          {
            "aria-label": @core.any("Export progress"),
            "value": @core.any(progress),
            "max": @core.any(1),
          },
          [],
        ),
        h("span", Map([]), ["\{round_number(progress * 100.0)}%"]),
      ]),
    )
  }
  if view is Completed(value, _) {
    let bytes : Double = value.output._get("blob")._get("size").cast()
    let dimensions = string_value(value.output._get("width")) +
      " × " +
      string_value(value.output._get("height"))
    status.push(
      h("div", { "className": @core.any("export-dialog-result") }, [
        h("p", Map([]), [icon("Check", 16), "書き出しが完了しました"]),
        h("span", Map([]), [
          dimensions +
          " · \{value.snapshot.fps} fps · " +
          fixed_number(bytes / 1024.0 / 1024.0, 1) +
          " MB",
        ]),
        h("small", Map([]), [value.filename]),
      ]),
    )
  }
  content.push(
    h(
      "div",
      {
        "className": @core.any("export-dialog-status"),
        "role": @core.any("status"),
        "aria-live": @core.any("polite"),
      },
      status,
    ),
  )
  let actions : Array[&@react.ReactNode] = [
    h(
      "button",
      {
        "className": @core.any("subtle-button"),
        "onClick": @core.any(
          if busy {
            cancel
          } else {
            fn() { change_open(false) }
          },
        ),
      },
      [if busy { "Cancel" } else { "Close" }],
    ),
  ]
  if view is Completed(value, _) {
    actions.push(
      h(
        "button",
        {
          "className": @core.any("subtle-button"),
          "onClick": @core.any(fn() { set_view(Ready) }),
        },
        [icon("RotateCcw", 14), "New export"],
      ),
    )
    actions.push(
      h(
        "button",
        {
          "className": @core.any("primary-button"),
          "onClick": @core.any(fn() { save_export(value, set_view) }),
        },
        [icon("Download", 15), "Download again"],
      ),
    )
  } else {
    actions.push(
      h(
        "button",
        {
          "className": @core.any("primary-button"),
          "onClick": @core.any(render),
          "disabled": @core.any(
            busy ||
            view is Checking ||
            !capabilities
            .map(fn(value) { value.supports(format) })
            .unwrap_or(false),
          ),
        },
        [
          if busy {
            icon("LoaderCircle", 15, props={
              "className": @core.any("loading-spinner"),
            })
          } else {
            icon("Download", 15)
          },
          "Export video",
        ],
      ),
    )
  }
  content.push(
    h(
      "div",
      { "className": @core.any("dialog-actions export-dialog-actions") },
      actions,
    ),
  )
  component(
    modal,
    {
      "open": @core.any(open),
      "onOpenChange": @core.any(change_open),
      "title": @core.any("Ready for the world."),
      "description": @core.any(
        title + " · " + fixed_number(duration / 1000.0, 2) + " seconds",
      ),
      "className": @core.any("export-dialog"),
    },
    content,
  )
}
