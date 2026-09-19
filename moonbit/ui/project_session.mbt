///|
priv enum ProjectAction {
  BlankProject
  DemoProject
  CalculusProject
  OpenProject(@core.Any)
  SaveProject(@core.Any)
}

///|
priv enum ProjectOperation {
  Opening
  Saving
}

///|
priv enum ProjectDialogView {
  Idle(String)
  Running(ProjectOperation)
}

///|
priv struct ProjectRequest {
  controller : @core.Any
}

///|
fn project_action_error(message : String) -> Unit raise {
  @core.throwable(fn() { @core.throw_error(message) })
}

///|
priv struct ProjectSession {
  mut mounted : Bool
  mut job : ProjectRequest?
  publish : (ProjectDialogView) -> Unit
}

///|
fn ProjectSession::owns(
  self : ProjectSession,
  request : ProjectRequest,
) -> Bool {
  self.mounted &&
  self.job
  .map(fn(current) { physical_equal(current, request) })
  .unwrap_or(false) &&
  !truthy(request.controller._get("signal")._get("aborted"))
}

///|
fn ProjectSession::cancel(self : ProjectSession) -> Unit {
  let previous = self.job
  self.job = None
  if previous is Some(previous) {
    previous.controller._call("abort", []) |> ignore
  }
  if self.mounted {
    (self.publish)(Idle(""))
  }
}

///|
fn blank_project() -> @core.Any {
  let id = @boundary.new_id("scene")
  @core.from_entries([
    ("version", @core.any(1)),
    ("name", @core.any("Untitled project")),
    ("sceneOrder", @core.any(([id] : FixedArray[String]))),
    (
      "scenes",
      @core.from_entries([(id, @boundary.make_blank_scene(id, "Scene 1"))]),
    ),
  ])
}

///|
fn project_filename(name : String) -> String {
  let result = StringBuilder()
  for char in name {
    result.write_char(
      if ['\\', '/', ':', '*', '?', '"', '<', '>', '|'].contains(char) {
        '_'
      } else {
        char
      },
    )
  }
  result.to_string() + ".poietra.json"
}

///|
fn ProjectSession::start(
  self : ProjectSession,
  action : ProjectAction,
  services : @core.Any,
) -> Unit {
  if !self.mounted || self.job is Some(_) {
    return
  }
  let controller = @core.new(@core.global_this()._get("AbortController"), [])
  let signal = controller._get("signal")
  let request : ProjectRequest = { controller, }
  let operation = match action {
    SaveProject(_) => ProjectOperation::Saving
    _ => Opening
  }
  self.job = Some(request)
  (self.publish)(Running(operation))
  @core.from_async(async fn() {
    let failure = Ref("")
    defer (if self.owns(request) {
      self.job = None
      (self.publish)(Idle(failure.val))
    })
    try {
      match action {
        SaveProject(project) => {
          let snapshot = ui_call(services, "portableProject", [project, signal])
          if !self.owns(request) {
            return
          }
          download_project_snapshot(snapshot)
        }
        _ => {
          let project = match action {
            BlankProject => blank_project()
            DemoProject => @boundary.make_demo_project()
            CalculusProject => @boundary.make_calculus_project()
            OpenProject(file) => {
              let size : Double = file._get("size").cast()
              if size > 134217728.0 {
                project_action_error(
                  "プロジェクトファイルは 128 MB 以下にしてください。",
                )
              }
              let text : String = ui_call(file, "text", []).cast()
              if !self.owns(request) {
                return
              }
              @core.throwable(fn() { @boundary.parse_project_file(text) })
            }
            SaveProject(_) => @core.undefined()
          }
          if !self.owns(request) {
            return
          }
          let url = ui_call(services, "createProjectRoom", [project, signal])
          if !self.owns(request) {
            return
          }
          @core.throwable(fn() {
            @core.global_this()
            ._get("location")
            ._call("assign", [url._get("href")])
          })
          |> ignore
        }
      }
    } catch {
      error =>
        if self.owns(request) {
          failure.val = error_message(
            ui_native_error(error),
            match operation {
              Saving => "保存できませんでした。"
              Opening => "プロジェクトを開けませんでした。"
            },
          )
        }
    }
  })
  |> ignore
}

///|
fn download_project_snapshot(snapshot : @core.Any) -> Unit raise {
  let global = @core.global_this()
  let blob = @core.throwable(fn() {
    let json = global
      ._get("JSON")
      ._call("stringify", [snapshot, @core.null(), @core.any(2)])
    @core.new(global._get("Blob"), [
      @core.any(([json] : FixedArray[@core.Any])),
      @core.from_entries([("type", @core.any("application/json"))]),
    ])
  })
  let bytes : Int = blob._get("size").cast()
  if bytes > 134217728 {
    project_action_error(
      "保存する素材や Scene を減らして、128 MB 以下にしてください。",
    )
  }
  @core.throwable(fn() {
    download_blob(blob, project_filename(snapshot._get("name").cast()))
  })
}
