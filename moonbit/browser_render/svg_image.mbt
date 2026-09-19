///|
fn aborted(signal : @core.Any) -> Bool {
  if @core.is_nullish(signal) {
    false
  } else {
    signal._get("aborted").cast()
  }
}

///|
fn image_abort_error() -> @core.Any {
  @core.new(@core.global_this()._get("DOMException"), [
    @core.any("フレームの描画をキャンセルしました。"),
    @core.any("AbortError"),
  ])
}

///|
fn image_check_abort(signal : @core.Any) -> Unit raise BrowserFailure {
  if aborted(signal) {
    raise BrowserFailure(image_abort_error())
  }
}

///|
fn normalize_image_failure(error : Error, signal : @core.Any) -> Error {
  let native = host_error(error)
  if aborted(signal) ||
    (
      !@core.is_nullish(native) &&
      @core.equal(native._get("name"), @core.any("AbortError"))
    ) {
    BrowserFailure(image_abort_error())
  } else {
    error
  }
}

///|
pub fn with_svg_image(
  svg : String,
  signal : @core.Any,
  draw : (@core.Any) -> @core.Any,
) -> @core.Promise[@core.Any] {
  @core.from_async(async fn() {
    image_check_abort(signal)
    let mut url : String? = None
    let mut image : @core.Any? = None
    let mut abort : (() -> Unit)? = None
    defer {
      if abort is Some(abort) && !@core.is_nullish(signal) {
        signal._call("removeEventListener", [
          @core.any("abort"),
          @core.any(abort),
        ])
        |> ignore
      }
      if image is Some(image) {
        image._set("onload", @core.null())
        image._set("onerror", @core.null())
        image._set("src", @core.any(""))
      }
      if url is Some(url) {
        @core.global_this()
        ._get("URL")
        ._call("revokeObjectURL", [@core.any(url)])
        |> ignore
      }
    }
    try {
      let global = @core.global_this()
      let image_url : String = @core.throwable(fn() {
        let blob = @core.new(global._get("Blob"), [
          @core.any(([svg] : FixedArray[String])),
          @core.from_entries([
            ("type", @core.any("image/svg+xml;charset=utf-8")),
          ]),
        ])
        global._get("URL")._call("createObjectURL", [blob]).cast()
      })
      url = Some(image_url)
      let loaded = @core.throwable(fn() { @core.new(global._get("Image"), []) })
      image = Some(loaded)
      let pending : @core.PromiseResolvers[Unit] = @core.Promise::withResolvers()
      let cancel = fn() { pending.reject(image_abort_error().cast()) }
      abort = Some(cancel)
      @core.throwable(fn() {
        loaded._set("onload", @core.any(fn() { pending.resolve(()) }))
        loaded._set(
          "onerror",
          @core.any(fn() {
            pending.reject(
              @core.new(global._get("Error"), [
                @core.any(
                  "フレームを画像に変換できませんでした。ページを再読み込みしてお試しください。",
                ),
              ]).cast(),
            )
          }),
        )
        if !@core.is_nullish(signal) {
          signal._call("addEventListener", [
            @core.any("abort"),
            @core.any(cancel),
          ])
          |> ignore
        }
        loaded._set("src", @core.any(image_url))
        if aborted(signal) {
          cancel()
        }
      })
      pending.promise.wait()
      image_check_abort(signal)
      let result = @core.throwable(fn() { draw(loaded) })
      image_check_abort(signal)
      result
    } catch {
      error => raise normalize_image_failure(error, signal)
    }
  })
  |> host_errors
}
