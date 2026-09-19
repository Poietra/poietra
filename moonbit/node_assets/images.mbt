///|
pub fn save_image(
  room : String,
  bytes : @buffer.Uint8Array,
) -> @core.Promise[String] {
  @core.from_async(async fn() {
    if !@assets.valid_room(room) {
      fail("Invalid room")
    }
    if bytes.length() > @assets.image_limit {
      fail("画像データは 1 MB 以下にしてください。")
    }
    if @assets.image_mime(@http.byte_header(bytes)[:]) is None {
      fail("PNG・JPEG・WebP の画像を選択してください。")
    }
    let root = directory(room, Image)
    let digest = @http.image_digest(bytes.as_any()).wait()
    let filename = resolve_path(root, digest)
    mkdir(root)
    commit(root, async fn() {
      if file_exists(filename) {
        return
      }
      let names : FixedArray[String] = @http.call_promise(files(), "readdir", [
          @core.any(root),
        ])
        .wait()
        .cast()
      let mut used = 0.0
      for name in names {
        if @assets.valid_digest(name) {
          let stat = @http.call_promise(files(), "stat", [
            @core.any(resolve_path(root, name)),
          ]).wait()
          used += (stat._get("size").cast() : Double)
        }
      }
      if used + bytes.length().to_double() >
        @assets.Image.room_limit().to_double() {
        fail(
          "この部屋の画像が保存できる容量を超えました。新しいプロジェクトを作成してください。",
        )
      }
      let temporary = filename + ".tmp"
      defer remove(temporary)
      write_file(temporary, bytes.as_any())
      rename(temporary, filename)
    })
    "/api/rooms/" + room + "/images/" + digest
  })
  |> @http.native_errors
}

///|
async fn read_image(request : @core.Any) -> @buffer.Uint8Array {
  let source = iterator(request)
  defer (try @http.call_promise(source, "return", []).wait() |> ignore catch {
    _ => ()
  })
  let bytes = @buffer.Uint8Array::from_size(@assets.image_limit)
  let mut size = 0
  while true {
    let step = @http.call_promise(source, "next", []).wait()
    if (step._get("done").cast() : Bool) {
      break
    }
    let chunk : @buffer.Uint8Array = step._get("value").cast()
    let length : Double = chunk.as_any()._get("byteLength").cast()
    if length > (@assets.image_limit - size).to_double() {
      fail("画像データは 1 MB 以下にしてください。")
    }
    @core.throwable(fn() { copy(bytes, chunk, size) })
    size += length.to_int()
  }
  slice(bytes, 0, size)
}

///|
pub fn handle_images(
  request : @core.Any,
  response : @core.Any,
  pathname : String,
) -> @core.Promise[Bool] {
  @core.from_async(async fn() {
    guard @assets.asset_route(pathname) is Some(route) && route.kind == Image else {
      return false
    }
    let method_ : String = request._get("method").cast()
    try {
      if route.digest is Some(digest) && (method_ == "GET" || method_ == "HEAD") {
        let path = resolve_path(directory(route.room, Image), digest)
        if !file_exists(path) {
          error_response(response, 404, "画像が見つかりません。")
          return true
        }
        let bytes : @buffer.Uint8Array = @http.call_promise(
            files(),
            "readFile",
            [@core.any(path)],
          )
          .wait()
          .cast()
        guard @assets.image_mime(@http.byte_header(bytes)[:]) is Some(mime) else {
          fail("画像を読み取れませんでした。")
          return true
        }
        let headers = @http.image_headers(mime)
        headers._set("Content-Length", @core.any(bytes.length()))
        response._call("writeHead", [@core.any(200), headers]) |> ignore
        response._call("end", [
          if method_ == "HEAD" {
            @core.undefined()
          } else {
            bytes.as_any()
          },
        ])
        |> ignore
        return true
      }
      if route.digest is Some(_) || method_ != "POST" {
        error_response(response, 405, "Method not allowed")
        return true
      }
      if !same_origin(request) {
        error_response(
          response, 403, "この編集画面から画像を追加してください。",
        )
        return true
      }
      let bytes = read_image(request)
      let source = save_image(route.room, bytes).wait()
      json(response, 200, @core.from_entries([("src", @core.any(source))]))
    } catch {
      error => reject_upload(response, request, error, Image)
    }
    true
  })
  |> @http.native_errors
}
