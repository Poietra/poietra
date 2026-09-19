///|
priv suberror UploadError {
  UploadError(@core.Any)
}

///|
fn native_error(error : Error) -> @core.Any {
  match error {
    UploadError(value) => value
    _ => @http.native_error(error)
  }
}

///|
fn[T] native_errors(promise : @core.Promise[T]) -> @core.Promise[T] {
  promise.catch_(fn(error) {
    @core.Promise::reject(native_error(error)).to_any().cast()
  })
}

///|
priv struct UploadScope {
  reader : @streams.ReadableStreamDefaultReader
  client_signal : @core.Any
  signal : @core.Any
  timer : @core.Any
  mut cancellation : @core.Promise[Unit]?
  mut on_abort : () -> Unit
}

///|
fn fail(message : String, status? : Int = 400) -> Unit raise {
  raise UploadError(
    @core.new(@http.media_error_type(), [@core.any(message), @core.any(status)]),
  )
}

///|
extern "js" fn has_instance(value : @core.Any, type_ : @core.Any) -> Bool =
  #|(value, type) => value instanceof type

///|
fn storage_error(error : Error) -> Error {
  let value = native_error(error)
  if has_instance(value, @http.media_error_type()) {
    UploadError(value)
  } else {
    UploadError(
      @core.new(@http.media_error_type(), [
        @core.any(
          "素材を保存できませんでした。もう一度お試しください。",
        ),
        @core.any(502),
      ]),
    )
  }
}

///|
fn UploadScope::interruption(self : UploadScope) -> Error {
  let cancelled : Bool = self.client_signal._get("aborted").cast()
  UploadError(
    @core.new(@http.media_error_type(), [
      @core.any(
        if cancelled {
          "アップロードを中止しました。"
        } else {
          "アップロードが時間内に完了しませんでした。もう一度お試しください。"
        },
      ),
      @core.any(if cancelled { 499 } else { 408 }),
    ]),
  )
}

///|
fn UploadScope::check(self : UploadScope) -> Unit raise {
  if (self.signal._get("aborted").cast() : Bool) {
    raise self.interruption()
  }
}

///|
fn UploadScope::cancel(self : UploadScope) -> @core.Promise[Unit] {
  match self.cancellation {
    Some(promise) => promise
    None => {
      let promise = @core.from_async(async fn() {
        self.reader.cancel() catch {
          _ => ()
        }
      })
      self.cancellation = Some(promise)
      promise
    }
  }
}

///|
async fn UploadScope::close(self : UploadScope) -> Unit {
  @core.global_this()._call("clearTimeout", [self.timer]) |> ignore
  self.signal._call("removeEventListener", [
    @core.any("abort"),
    @core.any(self.on_abort),
  ])
  |> ignore
  self.cancel().wait()
  self.reader.release_lock()
}

///|
fn open_scope(
  request : @core.Any,
  kind : @assets.AssetKind,
) -> UploadScope raise {
  let body = request._get("body")
  if @core.is_nullish(body) {
    fail(
      if kind == Image {
        "画像がありません。"
      } else {
        "音声・動画ファイルを選択してください。"
      },
    )
  }
  let stream : @streams.ReadableStream = body.cast()
  let reader = @core.throwable(fn() { stream.get_reader() })
  let global = @core.global_this()
  let deadline = @core.new(global._get("AbortController"), [])
  let timer = global._call("setTimeout", [
    @core.any(fn() { deadline._call("abort", []) |> ignore }),
    @core.any(300000),
  ])
  let client_signal = request._get("signal")
  let signal = global
    ._get("AbortSignal")
    ._call("any", [
      @core.any(
        ([client_signal, deadline._get("signal")] : FixedArray[@core.Any]),
      ),
    ])
  let scope : UploadScope = {
    reader,
    client_signal,
    signal,
    timer,
    cancellation: None,
    on_abort: fn() {  },
  }
  scope.on_abort = fn() { scope.cancel() |> ignore }
  signal._call("addEventListener", [
    @core.any("abort"),
    @core.any(scope.on_abort),
    @core.from_entries([("once", @core.any(true))]),
  ])
  |> ignore
  scope
}

///|
async fn UploadScope::read(
  self : UploadScope,
  kind : @assets.AssetKind,
) -> @core.Any {
  self.check()
  let result = self.reader.read() catch {
    _ => {
      self.check()
      fail(
        if kind == Image {
          "画像の読み込みが中断されました。もう一度お試しください。"
        } else {
          "素材の読み込みが中断されました。もう一度お試しください。"
        },
      )
      @core.undefined()
    }
  }
  self.check()
  result
}

///|
fn content_length(
  request : @core.Any,
  kind : @assets.AssetKind,
) -> Double? raise {
  guard @http.header(request._get("headers"), "Content-Length") is Some(header) else {
    return None
  }
  let value : Double = @core.global_this()
    ._call("Number", [@core.any(header)])
    .cast()
  if header.is_empty() ||
    !header.iter().all(fn(c) { c >= '0' && c <= '9' }) ||
    value > 9007199254740991.0 ||
    value.is_nan() {
    fail(
      if kind == Image {
        "画像のサイズが正しくありません。"
      } else {
        "素材のサイズが正しくありません。"
      },
    )
  }
  if value > kind.file_limit().to_double() {
    fail(
      if kind == Image {
        "画像データは 1 MB 以下にしてください。"
      } else {
        "音声・動画は 32 MB 以下にしてください。"
      },
      status=if kind == Image { 400 } else { 413 },
    )
  }
  if value == 0.0 {
    fail(
      if kind == Image {
        "画像がありません。"
      } else {
        "空の音声・動画ファイルは追加できません。"
      },
    )
  }
  Some(value)
}

///|
fn check_length(
  expected : Double?,
  size : Int,
  kind : @assets.AssetKind,
) -> Unit raise {
  if expected is Some(expected) && expected != size.to_double() {
    fail(
      if kind == Image {
        "画像のサイズが一致しません。もう一度お試しください。"
      } else {
        "素材のサイズが一致しません。もう一度お試しください。"
      },
    )
  }
}

///|
fn http_metadata(mime : String) -> @cf.R2HttpMetadata {
  {
    contentType: Some(mime),
    contentLanguage: None,
    contentDisposition: None,
    contentEncoding: None,
    cacheControl: Some("private, max-age=31536000, immutable"),
    cacheExpiry: None,
  }
}

///|
fn uploaded(size : Int, mime : String, digest : String) -> @core.Any {
  @core.from_entries([
    ("size", @core.any(size)),
    ("mime", @core.any(mime)),
    ("digest", @core.any(digest)),
  ])
}

///|
#external
priv type Hash

///|
#module("node:crypto")
extern "js" fn create_hash(algorithm : String) -> Hash = "createHash"

///|
extern "js" fn Hash::update(self : Hash, bytes : @buffer.Uint8Array) -> Unit =
  #|(hash, bytes) => { hash.update(bytes); }

///|
extern "js" fn Hash::digest(self : Hash) -> String =
  #|hash => hash.digest('hex')

///|
extern "js" fn slice(
  bytes : @buffer.Uint8Array,
  start : Int,
  end : Int,
) -> @buffer.Uint8Array =
  #|(bytes, start, end) => bytes.subarray(start, end)

///|
extern "js" fn copy(
  target : @buffer.Uint8Array,
  source : @buffer.Uint8Array,
  offset : Int,
) -> Unit =
  #|(target, source, offset) => target.set(source, offset)
