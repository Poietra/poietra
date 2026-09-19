///|
priv struct DownloadPolicy {
  kind : @assets.AssetKind
  limit : Int
  timeout : Int
  invalid : String
  missing : String
  failed : String
  oversized : String
}

///|
let image_policy : DownloadPolicy = {
  kind: @assets.Image,
  limit: @assets.image_limit,
  timeout: 15000,
  invalid: "画像の参照が正しくありません。",
  missing: "画像がありません。",
  failed: "共有画像を読み込めませんでした。接続を確認して再試行してください。",
  oversized: "画像が大きすぎます。",
}

///|
let media_policy : DownloadPolicy = {
  kind: @assets.Media,
  limit: @assets.media_limit,
  timeout: 120000,
  invalid: "素材の参照が正しくありません。",
  missing: "共有素材を読み込めませんでした。",
  failed: "共有素材を読み込めませんでした。",
  oversized: "素材が大きすぎます。",
}

///|
async fn cancel_reader(reader : @core.Any) -> Unit {
  try {
    let cancel : @core.Promise[Unit] = @core.throwable(fn() {
      reader._call("cancel", []).cast()
    })
    cancel.wait()
  } catch {
    _ => ()
  }
}

///|
async fn download(
  source : String,
  signal : @core.Any,
  policy : DownloadPolicy,
) -> @core.Any {
  check_abort(signal)
  if !@assets.valid_source(source, policy.kind) {
    raise MediaFailure(policy.invalid)
  }
  let global = @core.global_this()
  let timeout = global
    ._get("AbortSignal")
    ._call("timeout", [@core.any(policy.timeout)])
  let active = join_signal(timeout, signal)
  let pending : @core.Promise[@core.Any] = @core.throwable(fn() {
    global
    ._call("fetch", [
      @core.any(source),
      @core.from_entries([("signal", active)]),
    ])
    .cast()
  })
  let response = pending.wait()
  let ok : Bool = response._get("ok").cast()
  if !ok {
    raise MediaFailure(policy.failed)
  }
  let body = response._get("body")
  if @core.is_nullish(body) {
    raise MediaFailure(policy.missing)
  }
  let reader = @core.throwable(fn() { body._call("getReader", []) })
  defer reader._call("releaseLock", []) |> ignore
  let chunks : Array[@core.Any] = []
  let mut size = 0
  errdefer cancel_reader(reader)
  while true {
    check_abort(active)
    let pending : @core.Promise[@core.Any] = @core.throwable(fn() {
      reader._call("read", []).cast()
    })
    let chunk = pending.wait()
    if chunk._get("done").cast() {
      break
    }
    let value = chunk._get("value")
    let length : Int = value._get("byteLength").cast()
    if length > policy.limit - size {
      raise MediaFailure(policy.oversized)
    }
    size += length
    chunks.push(@core.throwable(fn() { copy_bytes(value) }))
  }
  check_abort(active)
  let mime : String = {
    let content_type = @core.throwable(fn() {
      response._get("headers")._call("get", [@core.any("Content-Type")])
    })
    let fallback = if policy.kind == @assets.Image {
      "image/png"
    } else {
      "application/octet-stream"
    }
    if @core.is_nullish(content_type) {
      fallback
    } else {
      let value : String = content_type.cast()
      let value = value.split(";").next().unwrap().to_owned()
      if value.is_empty() {
        fallback
      } else {
        value
      }
    }
  }
  @core.throwable(fn() {
    @core.new(global._get("Blob"), [
      @core.any(FixedArray::from_array(chunks[:])),
      @core.from_entries([("type", @core.any(mime))]),
    ])
  })
}

///|
pub fn image_blob(
  source : String,
  signal : @core.Any,
) -> @core.Promise[@core.Any] {
  @core.from_async(async fn() { download(source, signal, image_policy) })
  |> native_errors
}

///|
pub fn media_blob(
  source : String,
  signal : @core.Any,
) -> @core.Promise[@core.Any] {
  @core.from_async(async fn() { download(source, signal, media_policy) })
  |> native_errors
}

///|
pub fn blob_data_url(blob : @core.Any) -> @core.Promise[String] {
  @core.from_async(async fn() {
    let reader = @core.throwable(fn() {
      @core.new(@core.global_this()._get("FileReader"), [])
    })
    defer {
      reader._set("onload", @core.null())
      reader._set("onerror", @core.null())
    }
    let result : @core.PromiseResolvers[String] = @core.Promise::withResolvers()
    @core.throwable(fn() {
      reader._set(
        "onload",
        @core.any(fn() { result.resolve(reader._get("result").cast()) }),
      )
      reader._set(
        "onerror",
        @core.any(fn() {
          result.reject(
            @core.new(@core.global_this()._get("Error"), [
              @core.any("画像を読み取れませんでした。"),
            ]).cast(),
          )
        }),
      )
      reader._call("readAsDataURL", [blob]) |> ignore
    })
    result.promise.wait()
  })
  |> native_errors
}

///|
pub fn open_media(
  source : String,
  signal : @core.Any,
) -> @core.Promise[@core.Any] {
  @core.from_async(async fn() {
    let blob = download(source, signal, media_policy)
    check_abort(signal)
    let runtime = media_runtime().wait()
    check_abort(signal)
    @core.throwable(fn() {
      let source = @core.new(runtime._get("BlobSource"), [blob])
      @core.new(runtime._get("Input"), [
        @core.from_entries([
          ("source", source),
          ("formats", runtime._get("ALL_FORMATS")),
        ]),
      ])
    })
  })
  |> native_errors
}
