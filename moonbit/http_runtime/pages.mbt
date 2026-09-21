///|
pub fn prefers_markdown(accept : @core.Any) -> Bool {
  @policy.prefers_markdown(optional_string(accept))
}

///|
fn page_plan(url : @core.Any, headers : @core.Any) -> @policy.PagePlan? {
  let path : String = url._get("pathname").cast()
  let query = url._get("searchParams")
  let has = fn(key : String) -> Bool {
    query._call("has", [@core.any(key)]).cast()
  }
  @policy.page_plan(
    path,
    @site.editor_path(path, has("room"), has("projects"), has("auth_error")),
    optional_string(query._call("get", [@core.any("lang")])),
    header(headers, "Accept"),
    header(headers, "Accept-Language"),
    @locale.normalized_language,
  )
}

///|
pub fn public_page_plan(url : @core.Any, headers : @core.Any) -> @core.Any {
  match page_plan(url, headers) {
    None => @core.null()
    Some(plan) =>
      @core.from_entries([
        (
          "kind",
          @core.any(
            match plan.kind {
              @policy.Home => "home"
              @policy.Editor => "editor"
              @policy.Developers => "developers"
            },
          ),
        ),
        ("locale", @core.any(@site.locale_name(plan.locale))),
        ("assetPath", @core.any(plan.asset_path)),
        ("contentType", @core.any(plan.content_type)),
        ("headers", headers_object(plan.headers)),
      ])
  }
}

///|
pub fn fetch_public_page(
  request : @http.Request,
  fetch_asset : (@http.Request) -> @core.Promise[@http.Response],
) -> @core.Promise[@core.Any] {
  @core.from_async(async fn() {
    let method_ = request.method_()
    if method_ != "GET" && method_ != "HEAD" {
      return @core.null()
    }
    let url = @core.throwable(fn() {
      @core.new(@core.global_this()._get("URL"), [@core.any(request.url)])
    })
    let headers = request.as_any()._get("headers")
    guard page_plan(url, headers) is Some(plan) else { return @core.null() }
    let target = @core.new(@core.global_this()._get("URL"), [
      @core.any(plan.asset_path),
      url,
    ])
    let path : String = target._get("pathname").cast()
    if path.has_suffix("/index.html") {
      target._set("pathname", @core.any(path[:path.length() - 10].to_owned()))
    }
    let asset_request = @http.Request::new_with_init(
      target._get("href").cast(),
      @http.RequestInit::new(
        http_method=method_,
        headers=headers.cast(),
        redirect="manual",
      ),
    )
    let response = @core.throwable(fn() { fetch_asset(asset_request) }).wait()
    let response_headers = @core.new(@core.global_this()._get("Headers"), [
      response.as_any()._get("headers"),
    ])
    for (key, value) in plan.headers {
      let value = if key == "Vary" &&
        header(response_headers, key) is Some(existing) {
        @policy.merge_vary(existing, value)
      } else {
        value
      }
      response_headers._call("set", [@core.any(key), @core.any(value)])
      |> ignore
    }
    if response.ok || response.status == 304 {
      response_headers._call("set", [
        @core.any("Content-Type"),
        @core.any(plan.content_type),
      ])
      |> ignore
    }
    @http.Response::new_with_body(
      body=response.as_any()._get("body"),
      status=response.status,
      statusText=response.statusText,
      headers=response_headers,
    ).as_any()
  })
  |> native_errors
}
