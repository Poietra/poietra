///|
fn AccountController::refresh(self : AccountController) -> Unit {
  @core.from_async(async fn() { self.refresh_session() }) |> ignore
}

///|
fn AccountController::list(self : AccountController) -> Unit {
  @core.from_async(async fn() { self.refresh_projects() }) |> ignore
}

///|
fn AccountController::session_current(
  self : AccountController,
  request : @core.Any,
) -> Bool {
  self.mounted &&
  @core.equal(self.session_request, request) &&
  !ui_aborted(request._get("signal"))
}

///|
async fn AccountController::refresh_session(self : AccountController) -> Unit {
  account_cancel(self.session_request)
  let request = new_controller()
  self.session_request = request
  defer (if self.session_current(request) {
    self.update({ ..self.view, loading: false, })
  })
  try {
    let response = account_request(
      "/api/auth/session",
      host_record({ "signal": request._get("signal") }),
    )
    if !self.session_current(request) {
      return
    }
    let session = @core.throwable(fn() { account_session(response) })
    let identity = session.user.map(fn(user) { user.id })
    if self.identity != identity {
      account_cancel(self.list_request)
      if self.write is Some(write) {
        account_cancel(write.controller)
      }
      self.write = None
      self.identity = identity
      self.saved = None
      self.attempted = None
      self.update({
        ..self.view,
        projects: [],
        excluded: None,
        pending: "",
        list_loading: false,
      })
    }
    self.update({ ..self.view, session: Some(session), error: "", })
  } catch {
    failure =>
      if self.session_current(request) {
        self.update({
          ..self.view,
          error: error_message(
            ui_native_error(failure),
            "ログイン状態を確認できませんでした。",
          ),
        })
      }
  }
}

///|
fn AccountController::list_current(
  self : AccountController,
  request : @core.Any,
  identity : String,
) -> Bool {
  self.mounted &&
  self.identity == Some(identity) &&
  @core.equal(self.list_request, request) &&
  !ui_aborted(request._get("signal"))
}

///|
async fn AccountController::refresh_projects(self : AccountController) -> Unit {
  guard self.identity is Some(identity) else { return }
  account_cancel(self.list_request)
  let request = new_controller()
  self.list_request = request
  self.update({ ..self.view, list_loading: true, })
  defer (if self.list_current(request, identity) {
    self.update({ ..self.view, list_loading: false, })
  })
  try {
    let response = account_request(
      "/api/projects",
      host_record({
        "signal": request._get("signal"),
        "headers": host_record({ "X-Poietra-Account": @core.any(identity) }),
      }),
    )
    if self.list_current(request, identity) {
      let projects = @core.throwable(fn() {
        let values : FixedArray[@core.Any] = response._get("projects").cast()
        Array::makei(values.length(), fn(i) { account_project(values[i]) })
      })
      self.update({ ..self.view, projects, error: "", })
    }
  } catch {
    failure =>
      if self.list_current(request, identity) {
        self.update({
          ..self.view,
          error: error_message(
            ui_native_error(failure),
            "プロジェクト一覧を取得できませんでした。",
          ),
        })
        if account_failure(failure) {
          self.update({ ..self.view, projects: [], })
          self.refresh()
        }
      }
  }
}

///|
fn AccountController::owns_write(
  self : AccountController,
  request : AccountWrite,
) -> Bool {
  self.mounted &&
  self.write
  .map(fn(current) { @core.equal(@core.any(current), @core.any(request)) })
  .unwrap_or(false)
}

///|
fn AccountController::mutate(
  self : AccountController,
  operation : @editor.AccountOperation,
  current_room : String,
) -> Unit {
  @core.from_async(async fn() { self.mutate_async(operation, current_room) })
  |> ignore
}

///|
async fn AccountController::mutate_async(
  self : AccountController,
  operation : @editor.AccountOperation,
  current_room : String,
) -> Unit {
  guard self.identity is Some(identity) else { return }
  if self.write is Some(_) {
    return
  }
  let request : AccountWrite = {
    controller: new_controller(),
    identity,
    operation,
  }
  self.write = Some(request)
  self.update({
    ..self.view,
    pending: @editor.account_operation_key(operation),
    error: "",
  })
  defer (if self.owns_write(request) {
    self.write = None
    self.update({ ..self.view, pending: "", })
  })
  let signal = request.controller._get("signal")
  let headers = host_record({ "X-Poietra-Account": @core.any(identity) })
  try {
    let path = match operation {
      RememberProject(room, _) | RemoveProject(room) =>
        "/api/projects/" +
        string_value(
          @core.global_this()._call("encodeURIComponent", [@core.any(room)]),
        )
      SignOut => "/api/auth/logout"
    }
    let options = host_record({
      "signal": signal,
      "headers": headers,
      "method": @core.any(
        match operation {
          RememberProject(_, _) => "PUT"
          RemoveProject(_) => "DELETE"
          SignOut => "POST"
        },
      ),
    })
    if operation is @editor.RememberProject(_, name) {
      headers._set("Content-Type", @core.any("application/json"))
      options._set(
        "body",
        @core.global_this()
        ._get("JSON")
        ._call("stringify", [host_record({ "name": @core.any(name) })]),
      )
    }
    let response = account_request(path, options)
    if !self.owns_write(request) ||
      ui_aborted(signal) ||
      self.identity != Some(request.identity) {
      return
    }
    account_cancel(self.list_request)
    self.update({ ..self.view, list_loading: false, })
    match request.operation {
      RememberProject(room, name) => {
        let project = @core.throwable(fn() {
          account_project(response._get("project"))
        })
        self.saved = Some({ account: identity, room, name, })
        let projects = [project]
        for item in self.view.projects {
          if item.room_id != project.room_id {
            projects.push(item)
          }
        }
        self.update({ ..self.view, excluded: None, projects, })
        self.list()
      }
      RemoveProject(room) => {
        if room == current_room {
          self.saved = None
          self.update({
            ..self.view,
            excluded: Some({ account: identity, room, }),
          })
        }
        self.update({
          ..self.view,
          projects: self.view.projects.filter(fn(project) {
            project.room_id != room
          }),
        })
      }
      SignOut => {
        self.identity = None
        self.saved = None
        self.update({
          ..self.view,
          projects: [],
          pending: "",
          session: self.view.session.map(fn(session) {
            { ..session, user: None, }
          }),
        })
        self.refresh()
      }
    }
  } catch {
    failure =>
      if self.owns_write(request) &&
        !ui_aborted(signal) &&
        self.identity == Some(identity) {
        self.update({
          ..self.view,
          error: error_message(
            ui_native_error(failure),
            "更新できませんでした。",
          ),
        })
        if account_failure(failure) {
          self.update({ ..self.view, projects: [], })
          self.refresh()
        }
      }
  }
}
