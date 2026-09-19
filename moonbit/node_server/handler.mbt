///|
async fn Server::propose(
  self : Server,
  request : @core.Any,
  response : @core.Any,
) -> Unit {
  let api_key = string(self.env, "OPENAI_API_KEY")
  if api_key.is_empty() {
    error_response(
      response, 503, "AI はまだ接続されていません。接続が完了すると使えるようになります。",
    )
    return
  }
  let mut room = @core.undefined()
  let mut owns_request = false
  defer (if owns_request { room._set("aiBusy", @core.any(false)) })
  try {
    let value = @http.read_json(
      @core.from_entries([("body", web_body(request))]),
      @http.ai_request_limit,
    ).wait()
    let input = @core.throwable(fn() { @schemas.parse_ai_request(value) })
    room = @core.throwable(fn() {
      self.registry._call("getRoom", [input._get("roomId")])
    })
    let now : Double = @core.global_this()._get("Date")._call("now", []).cast()
    if (room._get("aiBusy").cast() : Bool) ||
      now - (room._get("aiLastRequest").cast() : Double) < 2000.0 {
      error_response(
        response, 429, "前の依頼を処理しています。少し待ってからお試しください。",
      )
      return
    }
    room._set("aiBusy", @core.any(true))
    room._set("aiLastRequest", @core.any(now))
    owns_request = true
    let proposal = @http.call_promise(self.runtime, "createEditProposal", [
      room._get("doc"),
      input,
      @core.any(api_key),
      @core.any(string(self.env, "OPENAI_MODEL", fallback="gpt-6-astra")),
      @core.from_entries([
        (
          "images",
          @core.from_entries([
            (
              "model",
              @core.any(
                string(self.env, "OPENAI_IMAGE_MODEL", fallback="gpt-image-1"),
              ),
            ),
            (
              "quality",
              @core.any(
                @ai.image_quality(self.env._get("OPENAI_IMAGE_QUALITY")),
              ),
            ),
            (
              "store",
              @core.any(fn(bytes) {
                @storage.save_image(string(input, "roomId"), bytes)
              }),
            ),
          ]),
        ),
        ("tuning", @ai.response_tuning(self.env)),
      ]),
    ]).wait()
    json(response, 200, proposal)
  } catch {
    error =>
      error_response(
        response,
        400,
        @ai.ai_error_message(@http.native_error(error), self.runtime._get("ai")),
      )
  }
}

///|
async fn Server::handle(
  self : Server,
  request : @core.Any,
  response : @core.Any,
) -> Unit {
  let url = location(request)
  let path = string(url, "pathname")
  let method_ = string(request, "method")
  let head = method_ == "HEAD"
  let page = if method_ == "GET" || head {
    @http.public_page_plan(
      url,
      @core.new(@core.global_this()._get("Headers"), [
        @http.headers_object([
          ("Accept", string(request._get("headers"), "accept")),
          (
            "Accept-Language",
            string(request._get("headers"), "accept-language"),
          ),
        ]),
      ]),
    )
  } else {
    @core.null()
  }
  if !@core.is_nullish(page) {
    for key in @core.object_keys(page._get("headers")) {
      response._call("setHeader", [
        @core.any(key),
        page._get("headers")._get(key),
      ])
      |> ignore
    }
    if self.production {
      let filename = resolve_path(
        self.static_root,
        "." + string(page, "assetPath"),
      )
      if !@fs.exists_sync(filename) {
        response._call("writeHead", [
          @core.any(503),
          @http.headers_object([("Cache-Control", "no-store")]),
        ])
        |> ignore
        response._call("end", [@core.any("Page is not built yet.")]) |> ignore
        return
      }
      response._call("writeHead", [
        @core.any(200),
        @http.headers_object([("Content-Type", string(page, "contentType"))]),
      ])
      |> ignore
      send_file(response, filename, head)
      return
    }
  }
  if path.has_prefix("/api/") || path.has_prefix("/sync/") {
    response._call("setHeader", [
      @core.any("X-Robots-Tag"),
      @core.any("noindex"),
    ])
    |> ignore
  }
  if path == "/api/health" {
    json(
      response,
      200,
      @core.from_entries([
        ("ok", @core.any(true)),
        ("ai", @core.any(!string(self.env, "OPENAI_API_KEY").is_empty())),
      ]),
    )
    return
  }
  let handled : Bool = (
    @core.throwable(fn() { self.auth._invoke([request, response]) }).cast() :
    @core.Promise[Bool]).wait()
  if handled ||
    @storage.handle_images(request, response, path).wait() ||
    @storage.handle_media(request, response, path).wait() {
    return
  }
  if path == "/api/ai/propose" && method_ == "POST" {
    self.propose(request, response)
    return
  }
  if path.has_prefix("/api/") {
    error_response(response, 404, "Not found")
    return
  }
  if !@core.is_nullish(self.vite) {
    self.vite._call("middlewares", [request, response]) |> ignore
    return
  }
  let mut filename = try {
    let decoded : String = @core.throwable(fn() {
      @core.global_this()._call("decodeURIComponent", [@core.any(path)]).cast()
    })
    resolve_path(self.static_root, "." + decoded)
  } catch {
    _ => {
      response._call("writeHead", [@core.any(400)]) |> ignore
      response._call("end", []) |> ignore
      return
    }
  }
  if !filename.has_prefix(self.static_root + "/") &&
    filename != self.static_root {
    response._call("writeHead", [@core.any(403)]) |> ignore
    response._call("end", []) |> ignore
    return
  }
  let mut status = 200
  if !@fs.exists_sync(filename) || @fs.stat_sync(filename).isDirectory() {
    filename = resolve_path(self.static_root, "404.html")
    if !@fs.exists_sync(filename) {
      response._call("writeHead", [@core.any(404)]) |> ignore
      response._call("end", [@core.any("Not found")]) |> ignore
      return
    }
    status = 404
    response._call("setHeader", [
      @core.any("X-Robots-Tag"),
      @core.any("noindex"),
    ])
    |> ignore
  }
  response._call("writeHead", [
    @core.any(status),
    @http.headers_object([
      ("Content-Type", content_type(filename)),
      (
        "Cache-Control",
        if filename.contains("/assets/") {
          "public, max-age=31536000, immutable"
        } else {
          "no-cache"
        },
      ),
    ]),
  ])
  |> ignore
  send_file(response, filename, head)
}
