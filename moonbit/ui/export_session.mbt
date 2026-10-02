///|
fn export_resolution_value(resolution : @exporting.Resolution) -> String {
  match resolution {
    Source => "source"
    ShortEdge(pixels) => "\{pixels}"
    Width(_) | Height(_) => "custom"
  }
}

///|
priv enum ExportRange {
  CurrentScene
  EntireProject
} derive(Eq)

///|
priv struct ExportSnapshot {
  range : ExportRange
  title : String
  duration : Double
  source_size : @exporting.Size
  scene_name : String
  name : String
  format : @exporting.Container
  fps : Double
  size : @exporting.Size
}

///|
// Only the active async operation owns document data. Running/completed dialog
// state retains small presentation values, including while saving again.
priv enum ExportInput {
  SceneInput(@core.Any)
  ProjectInput(@core.Any)
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
fn export_source_size(scene : @core.Any) -> @exporting.Size {
  { width: scene._get("width").cast(), height: scene._get("height").cast(), }
}

///|
fn first_export_scene(project : @core.Any, fallback : @core.Any) -> @core.Any {
  if @core.is_nullish(project) {
    return fallback
  }
  @boundary.first_project_scene(project).unwrap_or(fallback)
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
  resolution : @exporting.Resolution,
  range : ExportRange,
  session : ExportSession,
  active : @react.ReactRef[ExportJob],
  current : @react.ReactRef[@core.Any],
  set_view : (ExportView) -> Unit,
) -> Unit {
  let exporter = input._get("exporter")
  let (source, frozen) : (ExportInput, ExportSnapshot) = @core.throwable(fn() {
    let selected = selected_export_project(input, range)
    let project = if @core.is_nullish(selected) {
      selected
    } else {
      ui_snapshot(selected)
    }
    let is_project = !@core.is_nullish(project)
    let scene = if is_project {
      first_export_scene(project, input._get("scene"))
    } else {
      ui_snapshot(input._get("scene"))
    }
    let source_size = export_source_size(scene)
    let scene_name = string_value(scene._get("name"))
    let duration = if is_project {
      @boundary.project_duration(project)
    } else {
      @boundary.scene_duration(scene)
    }
    let size = @exporting.dimensions(source_size, resolution, format)
    match
      @exporting.plan(
        format.extension(),
        fps,
        source_size,
        Some(size.width),
        Some(size.height),
        [duration],
      ) {
      Err(message) => @core.throw_error(message)
      Ok(_) => ()
    }
    let frozen : ExportSnapshot = {
      range: if is_project {
        EntireProject
      } else {
        CurrentScene
      },
      title: if is_project {
        string_value(project._get("name")) +
        " · \{scene_count(project)} scenes"
      } else {
        scene_name
      },
      duration,
      source_size,
      scene_name,
      name: input._get("name").cast(),
      format,
      fps,
      size,
    }
    (if is_project { ProjectInput(project) } else { SceneInput(scene) }, frozen)
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
      let output = match source {
        ProjectInput(project) =>
          ui_call(exporter, "exportProject", [
            project,
            input._get("kernel"),
            settings,
          ])
        SceneInput(scene) =>
          ui_call(exporter, "exportScene", [
            scene,
            input._get("kernel"),
            settings,
          ])
      }
      if !job_is_current(job, active, current, exporter) {
        return
      }
      let suffix = if frozen.range == CurrentScene {
        "-" + frozen.scene_name
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
