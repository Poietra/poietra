///|
pub fn normalize_image(file : @core.Any) -> @core.Promise[@core.Any] {
  @core.from_async(async fn() {
    let mime : String = file._get("type").cast()
    if !["image/png", "image/jpeg", "image/webp"].contains(mime) {
      raise MediaFailure(
        "PNG・JPEG・WebP の画像を選択してください。",
      )
    }
    let size : Double = file._get("size").cast()
    if size > 20971520.0 {
      raise MediaFailure("元の画像は 20 MB 以下にしてください。")
    }
    let global = @core.global_this()
    let urls = global._get("URL")
    let source = @core.throwable(fn() { urls._call("createObjectURL", [file]) })
    defer urls._call("revokeObjectURL", [source]) |> ignore
    let image = @core.throwable(fn() { @core.new(global._get("Image"), []) })
    defer image._set("src", @core.any(""))
    @core.throwable(fn() { image._set("src", source) })
    try host_promise(image, "decode", []).wait() |> ignore catch {
      _ =>
        raise MediaFailure("この画像を読み取れませんでした。")
    }
    let width : Double = image._get("naturalWidth").cast()
    let height : Double = image._get("naturalHeight").cast()
    if width <= 0.0 || height <= 0.0 || width * height > 40000000.0 {
      raise MediaFailure(
        "画像の画素数が大きすぎます。4,000万画素以下にしてください。",
      )
    }
    let mut scale = 1.0.min(2048.0 / width.max(height))
    let canvas = @core.throwable(new_canvas)
    defer release_canvas(canvas)
    for attempt = 0; attempt < 8; attempt = attempt + 1 {
      let target_width = 1.0.max((width * scale).round())
      let target_height = 1.0.max((height * scale).round())
      let context = @core.throwable(fn() {
        canvas._set("width", @core.any(target_width))
        canvas._set("height", @core.any(target_height))
        canvas._call("getContext", [@core.any("2d")])
      })
      if @core.is_nullish(context) {
        raise MediaFailure("画像を準備できませんでした。")
      }
      @core.throwable(fn() {
        context._call("drawImage", [
          image,
          @core.any(0),
          @core.any(0),
          @core.any(target_width),
          @core.any(target_height),
        ])
      })
      |> ignore
      let result : @core.PromiseResolvers[@core.Any] = @core.Promise::withResolvers()
      @core.throwable(fn() {
        canvas._call("toBlob", [
          @core.any(result.resolve),
          @core.any(if attempt == 0 { "image/png" } else { "image/webp" }),
          @core.any(0.9),
        ])
      })
      |> ignore
      let blob = result.promise.wait()
      if !@core.is_nullish(blob) {
        let bytes : Int = blob._get("size").cast()
        if bytes <= @assets.image_limit {
          return @core.from_entries([
            ("blob", blob),
            ("width", @core.any(target_width)),
            ("height", @core.any(target_height)),
          ])
        }
      }
      if attempt > 0 {
        scale *= 0.75
      }
    }
    raise MediaFailure(
      "画像を小さくして、もう一度追加してください。",
    )
  })
  |> native_errors
}

///|
pub fn upload_image(
  room : String,
  blob : @core.Any,
  signal : @core.Any,
) -> @core.Promise[String] {
  @core.from_async(async fn() {
    check_abort(signal)
    let global = @core.global_this()
    let timeout = global
      ._get("AbortSignal")
      ._call("timeout", [@core.any(30000)])
    let active = join_signal(timeout, signal)
    let response = host_promise(global, "fetch", [
      @core.any("/api/rooms/" + room + "/images"),
      @core.from_entries([
        ("method", @core.any("POST")),
        ("headers", @core.from_entries([("Content-Type", blob._get("type"))])),
        ("body", blob),
        ("signal", active),
      ]),
    ]).wait()
    let data = host_promise(response, "json", []).wait() catch {
      error => {
        check_abort(active)
        ignore(error)
        raise MediaFailure(
          "画像を保存できませんでした。接続を確認して再試行してください。",
        )
      }
    }
    check_abort(active)
    let valid_object = !@core.is_nullish(data) &&
      @core.typeof_(data) == "object"
    let src = if valid_object { data._get("src") } else { @core.undefined() }
    let ok : Bool = response._get("ok").cast()
    if !ok ||
      @core.typeof_(src) != "string" ||
      !@assets.room_source(src.cast(), @assets.Image) {
      let error = if valid_object {
        data._get("error")
      } else {
        @core.undefined()
      }
      raise MediaFailure(
        if @core.typeof_(error) == "string" &&
          !@core.equal(error, @core.any("")) {
          error.cast()
        } else {
          "画像を保存できませんでした。"
        },
      )
    }
    src.cast()
  })
  |> native_errors
}
