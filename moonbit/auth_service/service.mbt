///|
fn route_provider(path : String, prefix : String) -> @policy.Provider? {
  if path.has_prefix(prefix) {
    @policy.provider(path[prefix.length():].to_owned())
  } else {
    None
  }
}

///|
async fn AuthService::projects(
  self : AuthService,
  request : @web.Request,
  target : @core.Any,
  path : String,
) -> @core.Any {
  guard self.session(request, target) is Some(session) else {
    return error_response(
      "一覧を表示するにはログインしてください。", 401,
    )
  }
  let expected = @http.header(
    request.as_any()._get("headers"),
    "X-Poietra-Account",
  )
  if expected is Some(expected) &&
    !expected.is_empty() &&
    expected != session.user.id {
    return error_response(
      "ログイン中のアカウントが変わりました。一覧を開き直してください。",
      409,
    )
  }
  let method_ = request.method_()
  if path == "/api/projects" && method_ == "GET" {
    let values = @http.call_promise(self.repository, "listProjects", [
      @core.any(session.user.id),
    ]).wait()
    return response(@core.from_entries([("projects", values)]))
  }
  guard path.has_prefix("/api/projects/") else {
    return error_response(
      "プロジェクトのリンクが正しくありません。", 400,
    )
  }
  let room = path[14:].to_owned()
  if !@assets.valid_room(room) {
    return error_response(
      "プロジェクトのリンクが正しくありません。", 400,
    )
  }
  if method_ == "PUT" {
    let value = bounded_json(request.as_any(), 2048) catch {
      _ =>
        return error_response(
          "プロジェクト名を確認してください。", 400,
        )
    }
    guard !@core.is_nullish(value) &&
      @core.typeof_(value) == "object" &&
      string(value, "name") is Some(name) &&
      !@editor.trim_text(name).is_empty() &&
      name.length() <= 200 else {
      return error_response(
        "プロジェクト名は 1〜200 文字で入力してください。",
        400,
      )
    }
    let project : @policy.Project = {
      room,
      name: @editor.trim_text(name).to_owned(),
      updated: (self.now)(),
    }
    let value = project_value(project)
    let accepted : Bool = @http.call_promise(self.repository, "putProject", [
        @core.any(session.user.id),
        value,
      ])
      .wait()
      .cast()
    if !accepted {
      return error_response(
        "一覧は 500 件まで保存できます。不要な項目を一覧から外してください。",
        409,
      )
    }
    return response(@core.from_entries([("project", value)]))
  }
  if method_ == "DELETE" {
    @http.call_promise(self.repository, "deleteProject", [
      @core.any(session.user.id),
      @core.any(room),
    ]).wait()
    |> ignore
    return response(@core.null(), status=204)
  }
  error_response("Not found", 404)
}

///|
async fn AuthService::handle(
  self : AuthService,
  request : @web.Request,
) -> @core.Any {
  let target = url(request.url)
  let path = get_string(target, "pathname")
  if !@policy.is_auth_path(path) {
    return @core.null()
  }
  try {
    let method_ = request.method_()
    if path == "/api/auth/session" && method_ == "GET" {
      let user = match self.session(request, target) {
        Some(session) => user_value(session.user)
        None => @core.null()
      }
      let providers = @core.from_entries([
        ("google", @core.any(self.enabled(target, Google))),
        ("github", @core.any(self.enabled(target, GitHub))),
      ])
      return response(
        @core.from_entries([("user", user), ("providers", providers)]),
      )
    }
    if method_ == "GET" &&
      route_provider(path, "/api/auth/login/") is Some(provider) {
      return self.login(target, provider)
    }
    if method_ == "GET" &&
      route_provider(path, "/api/auth/callback/") is Some(provider) {
      return self.callback(request, target, provider)
    }
    let headers = request.as_any()._get("headers")
    if method_ != "GET" &&
      @http.header(headers, "Origin") != Some(get_string(target, "origin")) {
      return error_response(
        "この編集画面から操作してください。", 403,
      )
    }
    if path == "/api/auth/logout" && method_ == "POST" {
      if @http.header(headers, "X-Poietra-Account") is Some(expected) &&
        !expected.is_empty() {
        if self.session(request, target) is Some(session) &&
          expected != session.user.id {
          return error_response(
            "ログイン中のアカウントが変わりました。一覧を開き直してください。",
            409,
          )
        }
      }
      if read_cookie(request, target, "session") is Some(token) {
        @http.call_promise(self.repository, "deleteRecord", [
          @core.any(record_key("session", token)),
        ]).wait()
        |> ignore
      }
      return response(@core.null(), status=204, cookies=[
        @policy.cookie(secure(target), "session", "", 0),
      ])
    }
    if path == "/api/projects" || path.has_prefix("/api/projects/") {
      return self.projects(request, target, path)
    }
    error_response("Not found", 404)
  } catch {
    _ =>
      error_response(
        "アカウント情報を取得できませんでした。少し待って再試行してください。",
        503,
      )
  }
}

///|
pub fn create_service(
  config : @core.Any,
  repository : @core.Any,
  transport : @core.Any,
  now : @core.Any,
) -> @core.Any {
  let service : AuthService = {
    config,
    repository,
    transport: if @core.is_nullish(transport) {
      fn(input, init) {
        @core.global_this()._call("fetch", [input, init]).cast()
      }
    } else {
      transport.cast()
    },
    now: if @core.is_nullish(now) {
      fn() { @core.global_this()._get("Date")._call("now", []).cast() }
    } else {
      now.cast()
    },
  }
  @core.from_entries([
    (
      "handle",
      @core.any(fn(request) {
        @core.from_async(async fn() { service.handle(request) })
        |> @http.native_errors
      }),
    ),
  ])
}

///|
extern "js" fn class_adapter(
  create : (@core.Any, @core.Any, @core.Any, @core.Any) -> @core.Any,
) -> @core.Any =
  #|create => function AuthService(config, repository, transport, now) { return create(config, repository, transport, now); }

///|
pub fn auth_class() -> @core.Any {
  class_adapter(create_service)
}
