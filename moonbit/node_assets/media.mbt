///|
async fn read_media(
  request : @core.Any,
  response : @core.Any,
  root : String,
  digest : String,
) -> Unit {
  let path = resolve_path(root, digest)
  let metadata = try {
    let metadata = read_json(path + ".json")
    let stat = @http.call_promise(files(), "stat", [@core.any(path)]).wait()
    if !@core.equal(stat._get("size"), metadata._get("size")) {
      fail("Incomplete asset")
    }
    metadata
  } catch {
    _ => {
      error_response(
        response, 404, "音声・動画が見つかりません。",
      )
      return
    }
  }
  let headers = request._get("headers")
  let method_ : String = request._get("method").cast()
  let if_range = headers._get("if-range")
  let array : Bool = @core.global_this()
    ._get("Array")
    ._call("isArray", [if_range])
    .cast()
  let plan = @http.media_response_plan(
    @core.from_entries([
      (
        "range",
        if method_ == "GET" {
          headers._get("range")
        } else {
          @core.null()
        },
      ),
      (
        "ifRange",
        if array {
          if_range._call("join", [@core.any(",")])
        } else {
          if_range
        },
      ),
      ("ifNoneMatch", headers._get("if-none-match")),
    ]),
    metadata,
    digest,
  )
  response._call("writeHead", [plan._get("status"), plan._get("headers")])
  |> ignore
  if @core.is_nullish(plan._get("range")) || method_ == "HEAD" {
    response._call("end", []) |> ignore
  } else {
    let stream = read_stream(path, plan._get("range"))
    stream._call("on", [
      @core.any("error"),
      @core.any(fn() { response._call("destroy", []) |> ignore }),
    ])
    |> ignore
    response._call("on", [
      @core.any("close"),
      @core.any(fn() { stream._call("destroy", []) |> ignore }),
    ])
    |> ignore
    stream._call("pipe", [response]) |> ignore
  }
}

///|
async fn publish_media(
  root : String,
  temporary : String,
  digest : String,
  metadata : @core.Any,
) -> Unit {
  let filename = resolve_path(root, digest)
  commit(root, async fn() {
    if file_exists(filename + ".json") {
      return
    }
    let names : FixedArray[String] = @http.call_promise(files(), "readdir", [
        @core.any(root),
      ])
      .wait()
      .cast()
    let mut used = 0.0
    for name in names {
      if name.length() == 69 &&
        name.has_suffix(".json") &&
        @assets.valid_digest(name[:64].to_owned()) {
        used += (
          read_json(resolve_path(root, name))._get("size").cast() : Double)
      }
    }
    if used + (metadata._get("size").cast() : Double) >
      @assets.Media.room_limit().to_double() {
      fail(
        "この部屋の音声・動画は合計 128 MB までです。新しいプロジェクトを作成してください。",
        status=413,
      )
    }
    rename(temporary, filename)
    let temporary_metadata = temporary + ".json"
    defer remove(temporary_metadata)
    write_file(temporary_metadata, @core.any(serialize(metadata)))
    rename(temporary_metadata, filename + ".json")
  })
}

///|
async fn receive_media(
  request : @core.Any,
  response : @core.Any,
  room : String,
  root : String,
) -> Unit {
  mkdir(root)
  let uuid : String = @core.global_this()
    ._get("crypto")
    ._call("randomUUID", [])
    .cast()
  let temporary = resolve_path(root, uuid + ".upload")
  let hash = create_hash("sha256")
  let file = @http.call_promise(files(), "open", [
    @core.any(temporary),
    @core.any("wx"),
    @core.any(384),
  ]).wait()
  defer {
    try @http.call_promise(file, "close", []).wait() |> ignore catch {
      _ => ()
    }
    remove(temporary)
  }
  let headers = request._get("headers")
  let metadata = @http.write_media_chunks(
    iterator(request),
    @http.optional_string(headers._get("content-type")).unwrap_or(""),
    headers._get("content-length"),
    fn(chunk, _part) {
      @core.from_async(async fn() {
        hash._call("update", [chunk.as_any()]) |> ignore
        let mut offset = 0
        while offset < chunk.length() {
          let written : Int = @http.call_promise(file, "write", [
              chunk.as_any(),
              @core.any(offset),
              @core.any(chunk.length() - offset),
            ])
            .wait()
            ._get("bytesWritten")
            .cast()
          // A stalled filesystem write must not spin forever while holding a request.
          if written <= 0 {
            fail(
              "素材を保存できませんでした。もう一度お試しください。",
            )
          }
          offset += written
        }
      }).to_any()
    },
  ).wait()
  @http.call_promise(file, "sync", []).wait() |> ignore
  @http.call_promise(file, "close", []).wait() |> ignore
  let digest : String = hash._call("digest", [@core.any("hex")]).cast()
  publish_media(root, temporary, digest, metadata)
  json(
    response,
    200,
    @core.from_entries([
      ("src", @core.any("/api/rooms/" + room + "/media/" + digest)),
    ]),
  )
}

///|
pub fn handle_media(
  request : @core.Any,
  response : @core.Any,
  pathname : String,
) -> @core.Promise[Bool] {
  @core.from_async(async fn() {
    guard @assets.asset_route(pathname) is Some(route) && route.kind == Media else {
      return false
    }
    let method_ : String = request._get("method").cast()
    let root = directory(route.room, Media)
    try {
      if route.digest is Some(digest) && (method_ == "GET" || method_ == "HEAD") {
        read_media(request, response, root, digest)
        return true
      }
      if route.digest is Some(_) || method_ != "POST" {
        error_response(response, 405, "Method not allowed")
        return true
      }
      if !same_origin(request) {
        error_response(
          response, 403, "この編集画面から音声・動画を追加してください。",
        )
        return true
      }
      receive_media(request, response, route.room, root)
    } catch {
      error => reject_upload(response, request, error, Media)
    }
    true
  })
  |> @http.native_errors
}
