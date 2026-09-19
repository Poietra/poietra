///|
priv enum ExportResolution {
  Source
  HD
  FullHD
} derive(Eq)

///|
fn ExportResolution::value(self : ExportResolution) -> String {
  match self {
    Source => "source"
    HD => "720"
    FullHD => "1080"
  }
}

///|
priv enum ExportRange {
  CurrentScene
  EntireProject
} derive(Eq)

///|
priv struct ExportSnapshot {
  scene : @core.Any
  project : @core.Any
  name : String
  format : @exporting.Container
  fps : Double
  size : @exporting.Size
}

///|
priv struct ExportSession {
  active : Ref[Bool]
}

///|
priv struct ExportJob {
  session : ExportSession
  controller : @core.Any
  snapshot : ExportSnapshot
  mut encoding : Bool
}

///|
priv struct ExportCompletion {
  output : @core.Any
  snapshot : ExportSnapshot
  filename : String
}

///|
priv enum ExportView {
  Checking
  Ready
  Running(ExportJob, Double)
  Canceled
  Completed(ExportCompletion, String)
  Failed(String)
}

///|
priv struct ExportCapabilities {
  mp4 : Bool
  webm : Bool
  reason : String
}

///|
fn ExportCapabilities::supports(
  self : ExportCapabilities,
  format : @exporting.Container,
) -> Bool {
  match format {
    Mp4 => self.mp4
    Webm => self.webm
  }
}

///|
fn export_dimensions(
  scene : @core.Any,
  resolution : ExportResolution,
  format : @exporting.Container,
) -> @exporting.Size {
  let width : Double = scene._get("width").cast()
  let height : Double = scene._get("height").cast()
  let scale = match resolution {
    Source => 1.0
    HD => 720.0 / width.min(height)
    FullHD => 1080.0 / width.min(height)
  }
  let unit = match format {
    Mp4 => 2.0
    Webm => 1.0
  }
  let size = fn(value : Double) {
    (round_number(value * scale / unit) * unit).max(unit)
  }
  { width: size(width), height: size(height), }
}

///|
fn first_export_scene(project : @core.Any, fallback : @core.Any) -> @core.Any {
  if @core.is_nullish(project) {
    return fallback
  }
  let segments = @boundary.project_segments(project)
  if segments.is_empty() {
    fallback
  } else {
    segments[0]._get("scene")
  }
}

///|
fn selected_export_project(input : @core.Any, range : ExportRange) -> @core.Any {
  if range == EntireProject &&
    truthy(input._get("project")) &&
    truthy(input._get("exporter")._get("exportProject")) {
    input._get("project")
  } else {
    @core.undefined()
  }
}

///|
fn ExportView::frozen(self : ExportView) -> ExportSnapshot? {
  match self {
    Running(job, _) => Some(job.snapshot)
    Completed(value, _) => Some(value.snapshot)
    _ => None
  }
}

///|
fn ExportView::message(self : ExportView) -> String {
  match self {
    Checking => "書き出しへの対応を確認しています…"
    Running(job, _) =>
      if job.encoding {
        "動画を書き出しています…"
      } else {
        "フォントと映像を準備しています…"
      }
    Canceled => "書き出しをキャンセルしました。"
    _ => ""
  }
}

///|
fn ExportView::error(self : ExportView) -> String {
  match self {
    Completed(_, message) | Failed(message) => message
    _ => ""
  }
}

///|
fn save_export(
  value : ExportCompletion,
  set_view : (ExportView) -> Unit,
) -> Unit {
  let error = try {
    save_blob(value.output._get("blob"), value.filename)
    ""
  } catch {
    _ =>
      "ダウンロードを開始できませんでした。もう一度保存してください。"
  }
  set_view(Completed(value, error))
}

///|
fn job_is_current(
  job : ExportJob,
  active : @react.ReactRef[ExportJob],
  current : @react.ReactRef[@core.Any],
  exporter : @core.Any,
) -> Bool {
  active
  .get_current()
  .map(fn(value) { @core.equal(@core.any(value), @core.any(job)) })
  .unwrap_or(false) &&
  job.session.active.val &&
  truthy(current.get_current().unwrap()._get("open")) &&
  @core.equal(current.get_current().unwrap()._get("exporter"), exporter) &&
  !ui_aborted(job.controller._get("signal"))
}

///|
fn begin_export(
  input : @core.Any,
  format : @exporting.Container,
  fps : Double,
  resolution : ExportResolution,
  range : ExportRange,
  session : ExportSession,
  active : @react.ReactRef[ExportJob],
  current : @react.ReactRef[@core.Any],
  set_view : (ExportView) -> Unit,
) -> Unit {
  let exporter = input._get("exporter")
  let frozen : ExportSnapshot = @core.throwable(fn() {
    let selected = selected_export_project(input, range)
    let project = if @core.is_nullish(selected) {
      selected
    } else {
      ui_snapshot(selected)
    }
    let scene = first_export_scene(project, input._get("scene"))
    {
      scene: ui_snapshot(scene),
      project,
      name: input._get("name").cast(),
      format,
      fps,
      size: export_dimensions(scene, resolution, format),
    }
  }) catch {
    error => {
      set_view(
        Failed(
          error_message(
            ui_native_error(error),
            "書き出しの準備に失敗しました。",
          ),
        ),
      )
      return
    }
  }
  let job : ExportJob = {
    session,
    controller: new_controller(),
    snapshot: frozen,
    encoding: false,
  }
  active.set_current(Some(job))
  set_view(Running(job, 0.0))
  @core.from_async(async fn() {
    try {
      let settings = @core.from_entries([
        ("format", @core.any(frozen.format.extension())),
        ("fps", @core.any(frozen.fps)),
        ("width", @core.any(frozen.size.width)),
        ("height", @core.any(frozen.size.height)),
        ("signal", job.controller._get("signal")),
        (
          "onProgress",
          @core.any(fn(value : Double) {
            if job_is_current(job, active, current, exporter) &&
              !value.is_nan() &&
              !value.is_inf() {
              if value > 0.0 {
                job.encoding = true
              }
              set_view(Running(job, value.max(0.0).min(1.0)))
            }
          }),
        ),
      ])
      let output = if !@core.is_nullish(frozen.project) &&
        truthy(exporter._get("exportProject")) {
        ui_call(exporter, "exportProject", [
          frozen.project,
          input._get("kernel"),
          settings,
        ])
      } else {
        ui_call(exporter, "exportScene", [
          frozen.scene,
          input._get("kernel"),
          settings,
        ])
      }
      if !job_is_current(job, active, current, exporter) {
        return
      }
      let suffix = if @core.is_nullish(frozen.project) {
        "-" + string_value(frozen.scene._get("name"))
      } else {
        ""
      }
      let result : ExportCompletion = {
        output,
        snapshot: frozen,
        filename: frozen.name +
        suffix +
        "." +
        string_value(output._get("extension")),
      }
      active.set_current(None)
      save_export(result, set_view)
    } catch {
      error =>
        if job_is_current(job, active, current, exporter) {
          active.set_current(None)
          set_view(
            Failed(
              error_message(
                ui_native_error(error),
                "書き出しに失敗しました。設定を変更して、もう一度お試しください。",
              ),
            ),
          )
        }
    }
  })
  |> ignore
}
