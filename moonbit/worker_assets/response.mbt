///|
pub fn asset_value(result : @core.Any) -> @core.Any {
  if !(result._get("ok").cast() : Bool) {
    @core.throw_(
      @core.new(@http.media_error_type(), [
        result._get("error"),
        result._get("status"),
      ]),
    )
  }
  result._get("value")
}

///|
fn json(value : @core.Any, status? : Int = 200) -> @core.Any {
  @web.Response::json_(
    value,
    options=@core.from_entries([
      ("status", @core.any(status)),
      (
        "headers",
        @http.headers_object([
          ("Cache-Control", "no-store"),
          ("X-Robots-Tag", "noindex"),
        ]),
      ),
    ]),
  ).as_any()
}

///|
fn error_response(message : String, status : Int) -> @core.Any {
  json(@core.from_entries([("error", @core.any(message))]), status~)
}

///|
extern "js" fn number_string(value : Double) -> String =
  #|value => String(value)

///|
extern "js" fn has_instance(value : @core.Any, type_ : @core.Any) -> Bool =
  #|(value, type) => value instanceof type

///|
async fn response(
  request : @web.Request,
  bucket : @cf.R2Bucket,
  kind : @assets.AssetKind,
  digest : String,
  metadata : @core.Any,
) -> @core.Any {
  guard @http.optional_string(metadata._get("objectKey")) is Some(key) &&
    !key.is_empty() else {
    return @core.null()
  }
  let method_ = request.method_()
  let size : Double = metadata._get("size").cast()
  let request_headers = request.as_any()._get("headers")
  let cached = @http.header(request_headers, "If-None-Match")
  let mut status = 200
  let mut range : @cf.R2Range? = None
  let headers = if kind == Media {
    let plan = @http.media_response_plan(
      @core.from_entries([
        (
          "range",
          if method_ == "GET" {
            request_headers._call("get", [@core.any("Range")])
          } else {
            @core.null()
          },
        ),
        ("ifRange", request_headers._call("get", [@core.any("If-Range")])),
        (
          "ifNoneMatch",
          request_headers._call("get", [@core.any("If-None-Match")]),
        ),
      ]),
      metadata,
      digest,
    )
    status = plan._get("status").cast()
    let native_range = plan._get("range")
    if !@core.is_nullish(native_range) {
      let start : Int = native_range._get("start").cast()
      let end : Int = native_range._get("end").cast()
      range = Some({
        offset: Some(start),
        length: Some(end - start + 1),
        suffix: None,
      })
    }
    plan._get("headers")
  } else {
    let headers = @http.image_headers(metadata._get("mime").cast())
    headers._set("ETag", @core.any("\"" + digest + "\""))
    if @policy.media_response(None, None, cached, size, digest) is Cached {
      status = 304
    } else {
      headers._set("Content-Length", @core.any(number_string(size)))
    }
    headers
  }
  headers._set("X-Robots-Tag", @core.any("noindex"))
  if status == 304 || status == 416 || method_ == "HEAD" {
    return @web.Response::new_with_body(body=@core.null(), status~, headers~).as_any()
  }
  guard @cloud.get(bucket, key, range) is Some(object) &&
    !@core.is_nullish(object.as_any()._get("body")) else {
    return @core.null()
  }
  if object.size().to_double() != size {
    object.body().cancel()
    @core.throwable(fn() {
      @core.throw_error("Stored asset size does not match its metadata")
    })
  }
  @web.Response::new_with_body(
    body=object.as_any()._get("body"),
    status~,
    headers~,
  ).as_any()
}

///|
pub fn asset_response(
  request : @web.Request,
  bucket : @cf.R2Bucket,
  kind : String,
  digest : String,
  metadata : @core.Any,
) -> @core.Promise[@core.Any] {
  @core.from_async(async fn() {
    match @assets.asset_kind(kind) {
      Some(kind) => response(request, bucket, kind, digest, metadata)
      None => @core.null()
    }
  })
  |> @http.native_errors
}

///|
pub fn handle_asset_request(
  request : @web.Request,
  env : @core.Any,
) -> @core.Promise[@core.Any] {
  @core.from_async(async fn() {
    let url = @core.new(@core.global_this()._get("URL"), [
      @core.any(request.url),
    ])
    guard @assets.asset_route(url._get("pathname").cast()) is Some(route) else {
      return @core.null()
    }
    let stub = env._get("ROOMS")._call("getByName", [@core.any(route.room)])
    let bucket : @cf.R2Bucket = env._get("MEDIA_BUCKET").cast()
    let method_ = request.method_()
    if route.digest is Some(digest) && (method_ == "GET" || method_ == "HEAD") {
      let metadata = @http.call_promise(stub, "getAssetMetadata", [
        @core.any(route.kind.name()),
        @core.any(digest),
      ]).wait()
      if @core.is_nullish(metadata) {
        return error_response(
          if route.kind == Image {
            "画像が見つかりません。"
          } else {
            "音声・動画が見つかりません。"
          },
          404,
        )
      }
      try {
        let result = response(request, bucket, route.kind, digest, metadata)
        if !@core.is_nullish(result) {
          return result
        }
      } catch {
        _ =>
          @core.global_this()
          ._get("console")
          ._call("warn", [@core.any("asset_r2_read_fallback")])
          |> ignore
      }
      return @http.call_promise(stub, "fetch", [request.as_any()]).wait()
    }
    if route.digest is Some(_) || method_ != "POST" {
      return error_response("Method not allowed", 405)
    }
    if @http.header(request.as_any()._get("headers"), "Origin") !=
      Some(url._get("origin").cast()) {
      return error_response(
        if route.kind == Image {
          "この編集画面から画像を追加してください。"
        } else {
          "この編集画面から音声・動画を追加してください。"
        },
        403,
      )
    }
    let (wrapped, input) = ingress(request, route.kind.file_limit())
    let mut key : String? = None
    defer {
      if key is Some(key) {
        try
          @http.call_promise(stub, "discardAssetUpload", [@core.any(key)]).wait()
          |> ignore
        catch {
          _ =>
            @core.global_this()
            ._get("console")
            ._call("warn", [@core.any("asset_cleanup_deferred")])
            |> ignore
        }
      }
      if input is Some(input) {
        input.close()
      }
    }
    try {
      let begun = @http.call_promise(stub, "beginAssetUpload", [
        @core.any(route.room),
        @core.any(route.kind.name()),
      ]).wait()
      let upload_key : String = @core.throwable(fn() {
        asset_value(begun).cast()
      })
      key = Some(upload_key)
      let metadata = match route.kind {
        Image =>
          @upload.upload_image_request(bucket, upload_key, wrapped.as_any()).wait()
        Media =>
          @upload.upload_media(bucket, upload_key, wrapped.as_any()).wait()
      }
      let finished = @http.call_promise(stub, "finishAssetUpload", [
        @core.any(upload_key),
        metadata._get("digest"),
        metadata._get("mime"),
        metadata._get("size"),
      ]).wait()
      @core.throwable(fn() { asset_value(finished) }) |> ignore
      let digest : String = metadata._get("digest").cast()
      json(
        @core.from_entries([
          (
            "src",
            @core.any(
              "/api/rooms/" +
              route.room +
              "/" +
              route.kind.name() +
              "/" +
              digest,
            ),
          ),
        ]),
      )
    } catch {
      error => {
        let value = @http.native_error(error)
        let message = if has_instance(value, @core.global_this()._get("Error")) {
          value._get("message").cast()
        } else {
          "素材を保存できませんでした。"
        }
        error_response(
          message,
          if has_instance(value, @http.media_error_type()) {
            value._get("status").cast()
          } else {
            400
          },
        )
      }
    }
  })
  |> @http.native_errors
}
