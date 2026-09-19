///|
fn json(value : @core.Any, status? : Int = 200) -> @core.Any {
  @core.global_this()
  ._get("Response")
  ._call("json", [
    value,
    @core.from_entries([
      ("status", @core.any(status)),
      (
        "headers",
        @http.headers_object([
          ("Cache-Control", "no-store"),
          ("X-Robots-Tag", "noindex"),
        ]),
      ),
    ]),
  ])
}

///|
fn error_response(message : String, status : Int) -> @core.Any {
  json(@core.from_entries([("error", @core.any(message))]), status~)
}

///|
async fn rate_limit(binding : @core.Any, request : @core.Any) -> Bool {
  let ip = @http.header(request._get("headers"), "CF-Connecting-IP").unwrap_or(
    "local",
  )
  let result = @http.call_promise(binding, "limit", [
    @core.from_entries([
      ("key", @core.any(if ip.is_empty() { "local" } else { ip })),
    ]),
  ]).wait()
  result._get("success").cast()
}

///|
pub fn handle_request(
  request : @core.Any,
  env : @core.Any,
  runtime : @core.Any,
) -> @core.Promise[@core.Any] {
  @core.from_async(async fn() {
    let url = @core.new(@core.global_this()._get("URL"), [request._get("url")])
    let path : String = url._get("pathname").cast()
    let method_ : String = request._get("method").cast()
    let page = @http.fetch_public_page(request.cast(), fn(asset_request) {
      env._get("ASSETS")._call("fetch", [@core.any(asset_request)]).cast()
    }).wait()
    if !@core.is_nullish(page) {
      return page
    }
    let api_key = @http.optional_string(env._get("OPENAI_API_KEY")).unwrap_or(
      "",
    )
    if path == "/api/health" {
      return json(
        @core.from_entries([
          ("ok", @core.any(true)),
          ("ai", @core.any(!api_key.is_empty())),
        ]),
      )
    }
    if method_ == "GET" &&
      (path == "/api/auth/login/google" || path == "/api/auth/login/github") {
      if !rate_limit(env._get("AUTH_LIMIT"), request) {
        return error_response(
          "ログインの試行が続いています。少し待って再試行してください。",
          429,
        )
      }
    }
    let account = @http.call_promise(@accounts.worker_auth(env), "handle", [
      request,
    ]).wait()
    if !@core.is_nullish(account) {
      return account
    }
    let asset = @storage.handle_asset_request(request.cast(), env).wait()
    if !@core.is_nullish(asset) {
      return asset
    }
    if path.has_prefix("/sync/") {
      let room = path[6:].to_owned()
      if !@assets.valid_room(room) {
        return error_response("Invalid room", 400)
      }
      if @http.header(request._get("headers"), "Upgrade")
        .unwrap_or("")
        .to_lower() !=
        "websocket" {
        return error_response("WebSocket required", 426)
      }
      return @http.call_promise(
        env._get("ROOMS")._call("getByName", [@core.any(room)]),
        "fetch",
        [request],
      ).wait()
    }
    if path == "/api/ai/propose" && method_ == "POST" {
      if api_key.is_empty() {
        return error_response(
          "AI はまだ接続されていません。接続が完了すると使えるようになります。",
          503,
        )
      }
      if !@core.equal(
          request._get("headers")._call("get", [@core.any("Origin")]),
          url._get("origin"),
        ) {
        return error_response(
          "この編集画面から依頼してください。", 403,
        )
      }
      if !rate_limit(env._get("AI_LIMIT"), request) {
        return error_response(
          "少し待ってから、もう一度お試しください。", 429,
        )
      }
      try {
        let value = @http.read_json(request, @http.ai_request_limit).wait()
        let input = @core.throwable(fn() { @schemas.parse_ai_request(value) })
        let room = env._get("ROOMS")._call("getByName", [input._get("roomId")])
        let result = @http.call_promise(room, "propose", [input]).wait()
        return json(result._get("body"), status=result._get("status").cast())
      } catch {
        error =>
          return error_response(
            @ai.ai_error_message(@http.native_error(error), runtime),
            400,
          )
      }
    }
    if path.has_prefix("/api/") {
      return error_response("Not found", 404)
    }
    @http.call_promise(env._get("ASSETS"), "fetch", [request]).wait()
  })
  |> @http.native_errors
}
