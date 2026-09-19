///|
#module("#poietra/node-host")
extern "js" fn files() -> @core.Any = "fileSystemPromises"

///|
#module("node:path")
extern "js" fn resolve_path(left : String, right : String) -> String = "resolve"

///|
#module("node:fs")
extern "js" fn read_stream(path : String, range : @core.Any) -> @core.Any = "createReadStream"

///|
#module("node:crypto")
extern "js" fn create_hash(algorithm : String) -> @core.Any = "createHash"

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

///|
extern "js" fn has_instance(value : @core.Any, type_ : @core.Any) -> Bool =
  #|(value, type) => value instanceof type

///|
fn directory(room : String, kind : @assets.AssetKind) -> String {
  let env = @core.global_this()
    ._get("process")
    ._get("env")
    ._get("POIETRA_DATA_DIR")
  let base = if @core.is_nullish(env) || @core.equal(env, @core.any("")) {
    ".data"
  } else {
    env.cast()
  }
  resolve_path(resolve_path(base, kind.name()), room)
}

///|
fn serialize(value : @core.Any) -> String {
  @core.global_this()._get("JSON")._call("stringify", [value]).cast()
}

///|
async fn read_json(path : String) -> @core.Any {
  let text = @http.call_promise(files(), "readFile", [
    @core.any(path),
    @core.any("utf8"),
  ]).wait()
  @core.throwable(fn() {
    @core.global_this()._get("JSON")._call("parse", [text])
  })
}

///|
async fn file_exists(path : String) -> Bool {
  try {
    @http.call_promise(files(), "stat", [@core.any(path)]).wait() |> ignore
    true
  } catch {
    _ => false
  }
}

///|
async fn remove(path : String) -> Unit {
  @http.call_promise(files(), "rm", [
    @core.any(path),
    @core.from_entries([("force", @core.any(true))]),
  ]).wait()
  |> ignore
}

///|
fn json(response : @core.Any, status : Int, value : @core.Any) -> Unit {
  response._call("writeHead", [
    @core.any(status),
    @http.headers_object([
      ("Content-Type", "application/json"),
      ("Cache-Control", "no-store"),
    ]),
  ])
  |> ignore
  response._call("end", [@core.any(serialize(value))]) |> ignore
}

///|
fn error_response(response : @core.Any, status : Int, message : String) -> Unit {
  json(response, status, @core.from_entries([("error", @core.any(message))]))
}

///|
async fn reject_upload(
  response : @core.Any,
  request : @core.Any,
  error : Error,
  kind : @assets.AssetKind,
) -> Unit {
  if !(request._get("complete").cast() : Bool) {
    // A TCP reset immediately after response.finish can discard a 413 while the
    // client is still writing. Drain a bounded, promptly arriving remainder first.
    response._set("shouldKeepAlive", @core.any(false))
    drain_rejected(request, kind.file_limit())
  }
  let value = @http.native_error(error)
  if !(response._get("headersSent").cast() : Bool) &&
    !(response._get("destroyed").cast() : Bool) {
    let status : Int = if has_instance(value, @http.media_error_type()) {
      value._get("status").cast()
    } else {
      400
    }
    let message : String = if has_instance(
        value,
        @core.global_this()._get("Error"),
      ) {
      value._get("message").cast()
    } else if kind == Image {
      "画像を保存できませんでした。"
    } else {
      "音声・動画を保存できませんでした。"
    }
    error_response(response, status, message)
  }
}

///|
async fn drain_rejected(request : @core.Any, limit : Int) -> Unit {
  let timeout : @core.PromiseResolvers[@core.Any] = @core.Promise::withResolvers()
  let timer = @core.global_this()._call("setTimeout", [
    @core.any(fn() {
      timeout.reject(
        @core.new(@core.global_this()._get("Error"), [
          @core.any("Upload drain deadline"),
        ]).cast(),
      )
    }),
    @core.any(2000),
  ])
  defer @core.global_this()._call("clearTimeout", [timer]) |> ignore
  let source = iterator(request)
  // Never wait for return() behind a stalled next(); closing the HTTP response
  // owns the socket. Observe rejection so cancellation cannot leak a promise.
  defer (try
    @http.call_promise(source, "return", []).catch_(fn(_error) {
      @core.Promise::resolve(@core.undefined())
    })
    |> ignore
  catch {
    _ => ()
  })
  let mut discarded = 0.0
  try {
    while discarded <= (limit + 131072).to_double() {
      let next = @http.call_promise(source, "next", [])
      let race : @core.Promise[@core.Any] = @core.global_this()
        ._get("Promise")
        ._call("race", [
          @core.any(
            ([next, timeout.promise] : FixedArray[@core.Promise[@core.Any]]),
          ),
        ])
        .cast()
      let result = race.wait()
      if (result._get("done").cast() : Bool) {
        break
      }
      discarded += (result._get("value")._get("byteLength").cast() : Double)
    }
  } catch {
    _ => ()
  }
}

///|
fn same_origin(request : @core.Any) -> Bool raise {
  let headers = request._get("headers")
  guard @http.optional_string(headers._get("origin")) is Some(origin) &&
    !origin.is_empty() else {
    return false
  }
  let url = @core.throwable(fn() {
    @core.new(@core.global_this()._get("URL"), [@core.any(origin)])
  })
  @core.equal(url._get("host"), headers._get("host"))
}

///|
fn fail(message : String, status? : Int = 400) -> Unit raise {
  @core.throwable(fn() {
    @core.throw_(
      @core.new(@http.media_error_type(), [
        @core.any(message),
        @core.any(status),
      ]),
    )
  })
}

///|
let commits : Map[String, @core.Promise[Unit]] = Map([])

///|
/// Serialize only quota checks and publication. Each upload owns its own file.
async fn[T] commit(directory : String, action : async () -> T) -> T {
  let previous = commits.get(directory).unwrap_or(@core.Promise::resolve(()))
  let release : @core.PromiseResolvers[Unit] = @core.Promise::withResolvers()
  let tail = @core.from_async(async fn() {
    previous.wait()
    release.promise.wait()
  })
  commits[directory] = tail
  previous.wait()
  defer {
    release.resolve(())
    if commits.get(directory) is Some(current) &&
      @core.equal(current.to_any(), tail.to_any()) {
      commits.remove(directory)
    }
  }
  action()
}

///|
fn iterator(request : @core.Any) -> @core.Any {
  request._call("iterator", [
    @core.from_entries([("destroyOnReturn", @core.any(false))]),
  ])
}

///|
async fn mkdir(path : String) -> Unit {
  @http.call_promise(files(), "mkdir", [
    @core.any(path),
    @core.from_entries([("recursive", @core.any(true))]),
  ]).wait()
  |> ignore
}

///|
async fn rename(from : String, to : String) -> Unit {
  @http.call_promise(files(), "rename", [@core.any(from), @core.any(to)]).wait()
  |> ignore
}

///|
async fn write_file(path : String, bytes : @core.Any) -> Unit {
  @http.call_promise(files(), "writeFile", [
    @core.any(path),
    bytes,
    @core.from_entries([("mode", @core.any(384))]),
  ]).wait()
  |> ignore
}
