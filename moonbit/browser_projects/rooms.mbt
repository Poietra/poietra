///|
fn dispose_host(value : @core.Any) -> Unit {
  try @core.throwable(fn() { value._call("destroy", []) }) |> ignore catch {
    _ => ()
  }
}

///|
/// Leave room below the server frame and SQLite row limits.
let project_message_bytes : Int = 1048576

///|
/// Include UTF-8 and Yjs overhead when grouping small entries.
let staging_budget : Int = 262144

///|
/// Leave echo-queue headroom; one indivisible frame may exceed this window.
let publication_window_bytes : Int = 524288

///|
let publication_window_messages : Int = 16

///|
fn project_messages(
  source : @core.Any,
  project : @core.Any,
  runtime : @core.Any,
) -> @core.Any raise {
  let yjs = runtime._get("Y")
  let staged = @core.throwable(fn() { @core.new(yjs._get("Doc"), []) })
  defer dispose_host(staged)
  @core.throwable(fn() {
    yjs._call("applyUpdate", [
      staged,
      yjs._call("encodeStateAsUpdate", [source]),
    ])
    |> ignore
    let updates : Array[@core.Any] = []
    let collect = fn(update : @core.Any) { updates.push(update) }
    staged._call("on", [@core.any("update"), @core.any(collect)]) |> ignore
    let root = staged._call("getMap", [@core.any("project")])
    staged._call("transact", [
      @core.any(fn() { root._call("clear", []) |> ignore }),
    ])
    |> ignore
    @boundary.fill_shared_bounded(staged, root, project, yjs, staging_budget)
    staged._call("off", [@core.any("update"), @core.any(collect)]) |> ignore
    let encoding = runtime._get("encoding")
    let sync = runtime._get("sync")
    let messages = FixedArray::makei(updates.length(), fn(index) {
      let update = encoding._call("createEncoder", [])
      encoding._call("writeVarUint", [update, @core.any(0)]) |> ignore
      sync._call("writeUpdate", [update, updates[index]]) |> ignore
      let message = encoding._call("toUint8Array", [update])
      let bytes : Int = message._get("byteLength").cast()
      if bytes > project_message_bytes {
        @core.throw_error(
          "1 MB を超える値が含まれているため、このプロジェクトは開けません。",
        )
      }
      message
    })
    let request = encoding._call("createEncoder", [])
    encoding._call("writeVarUint", [request, @core.any(0)]) |> ignore
    sync._call("writeSyncStep1", [request, staged]) |> ignore
    @core.from_entries([
      ("updateMessages", @core.any(messages)),
      ("syncMessage", encoding._call("toUint8Array", [request])),
    ])
  })
}

///|
pub fn create_project_messages(
  source : @core.Any,
  project : @core.Any,
  runtime : @core.Any,
) -> @core.Any {
  project_messages(source, project, runtime) catch {
    error => {
      @core.throw_(native_error(error))
      @core.undefined()
    }
  }
}

///|
priv enum PublishPhase {
  Connecting
  AwaitingAck(@core.Any, Publication)
  Finished(@core.Any?)
}

///|
priv struct Publication {
  updates : FixedArray[@core.Any]
  sync_message : @core.Any
  mut next : Int
}

///|
fn Publication::send_window(
  self : Publication,
  socket : @core.Any,
) -> Unit raise {
  @core.throwable(fn() {
    let mut bytes = 0
    let mut count = 0
    while self.next < self.updates.length() &&
          count < publication_window_messages {
      let update = self.updates[self.next]
      let size : Int = update._get("byteLength").cast()
      if count > 0 && bytes + size > publication_window_bytes {
        break
      }
      socket._call("send", [update]) |> ignore
      self.next += 1
      count += 1
      bytes += size
    }
    // The final state vector keeps intermediate persisted acknowledgments small.
    socket._call("send", [self.sync_message]) |> ignore
  })
}

///|
fn PublishPhase::socket(self : PublishPhase) -> @core.Any? {
  match self {
    Connecting => None
    AwaitingAck(socket, _) => Some(socket)
    Finished(socket) => socket
  }
}

///|
extern "js" fn is_array_buffer(value : @core.Any) -> Bool =
  #|value => value instanceof ArrayBuffer

///|
async fn publish_room(
  provider : @core.Any,
  doc : @core.Any,
  project : @core.Any,
  signal : @core.Any,
  runtime : @core.Any,
) -> Unit {
  let result : @core.PromiseResolvers[Unit] = @core.Promise::withResolvers()
  let phase = Ref(PublishPhase::Connecting)
  let finish = fn(error : @core.Any?) {
    if phase.val is Finished(_) {
      return
    }
    phase.val = Finished(phase.val.socket())
    match error {
      Some(error) => result.reject(error.cast())
      None => result.resolve(())
    }
  }
  let global = @core.global_this()
  let abort = fn() {
    finish(
      Some(
        @core.new(global._get("DOMException"), [
          @core.any("Canceled"),
          @core.any("AbortError"),
        ]),
      ),
    )
  }
  let timeout : Ref[@core.Any?] = Ref(None)
  let await_progress = fn() {
    if timeout.val is Some(previous) {
      global._call("clearTimeout", [previous]) |> ignore
    }
    timeout.val = Some(
      global._call("setTimeout", [
        @core.any(fn() {
          finish(
            Some(
              native_error(
                ProjectFailure(
                  "接続できませんでした。通信を確認して、もう一度開いてください。",
                ),
              ),
            ),
          )
        }),
        @core.any(15000),
      ]),
    )
  }
  await_progress()
  defer (if timeout.val is Some(timeout) {
    global._call("clearTimeout", [timeout]) |> ignore
  })
  let status = fn(event : @core.Any) {
    if phase.val is AwaitingAck(_, _) &&
      @core.equal(event._get("status"), @core.any("disconnected")) {
      finish(
        Some(
          native_error(
            ProjectFailure(
              "接続が切れました。もう一度開いてください。",
            ),
          ),
        ),
      )
    }
  }
  let acknowledged = fn(event : @core.Any) {
    guard phase.val is AwaitingAck(socket, publication) &&
      is_array_buffer(event._get("data")) else {
      return
    }
    let acknowledged : Bool = @core.throwable(fn() {
      let decoding = runtime._get("decoding")
      let decoder = decoding._call("createDecoder", [
        @core.new(global._get("Uint8Array"), [event._get("data")]),
      ])
      let message : Int = decoding._call("readVarUint", [decoder]).cast()
      message == 0 &&
      @core.equal(
        decoding._call("readVarUint", [decoder]),
        runtime._get("sync")._get("messageYjsSyncStep2"),
      )
    }) catch {
      _ => false
    }
    if acknowledged {
      if publication.next == publication.updates.length() {
        finish(None)
      } else {
        await_progress()
        publication.send_window(socket) catch {
          error => finish(Some(native_error(error)))
        }
      }
    }
  }
  let synced = fn(value : Bool) {
    if !value || !(phase.val is Connecting) {
      return
    }
    try {
      let socket = provider._get("ws")
      if @core.is_nullish(socket) ||
        !@core.equal(
          socket._get("readyState"),
          global._get("WebSocket")._get("OPEN"),
        ) {
        raise ProjectFailure("接続できませんでした。")
      }
      let messages = project_messages(doc, project, runtime)
      let publication : Publication = {
        updates: messages._get("updateMessages").cast(),
        sync_message: messages._get("syncMessage"),
        next: 0,
      }
      phase.val = AwaitingAck(socket, publication)
      @core.throwable(fn() {
        socket._call("addEventListener", [
          @core.any("message"),
          @core.any(acknowledged),
        ])
        |> ignore
      })
      await_progress()
      publication.send_window(socket)
    } catch {
      error => finish(Some(native_error(error)))
    }
  }
  defer {
    if !@core.is_nullish(signal) {
      signal._call("removeEventListener", [@core.any("abort"), @core.any(abort)])
      |> ignore
    }
    provider._call("off", [@core.any("sync"), @core.any(synced)]) |> ignore
    provider._call("off", [@core.any("status"), @core.any(status)]) |> ignore
    if phase.val.socket() is Some(socket) {
      socket._call("removeEventListener", [
        @core.any("message"),
        @core.any(acknowledged),
      ])
      |> ignore
    }
  }
  try {
    check_abort(signal)
    @core.throwable(fn() {
      if !@core.is_nullish(signal) {
        signal._call("addEventListener", [
          @core.any("abort"),
          @core.any(abort),
          @core.from_entries([("once", @core.any(true))]),
        ])
        |> ignore
      }
      provider._call("on", [@core.any("sync"), @core.any(synced)]) |> ignore
      provider._call("on", [@core.any("status"), @core.any(status)]) |> ignore
      provider._call("connect", []) |> ignore
    })
  } catch {
    error => finish(Some(native_error(error)))
  }
  result.promise.wait()
  check_abort(signal)
}

///|
pub fn create_project_room(
  project : @core.Any,
  signal : @core.Any,
  runtime : @core.Any,
) -> @core.Promise[@core.Any] {
  @core.from_async(async fn() {
    check_abort(signal)
    let global = @core.global_this()
    let room = global._get("crypto")._call("randomUUID", [])
    let project = host_call(runtime, "storeProjectImages", [
      project, room, signal,
    ])
    check_abort(signal)
    let doc = @core.throwable(fn() {
      @core.new(runtime._get("Y")._get("Doc"), [])
    })
    defer dispose_host(doc)
    let location = global._get("location")
    let protocol = if @core.equal(
        location._get("protocol"),
        @core.any("https:"),
      ) {
      "wss:"
    } else {
      "ws:"
    }
    let host : String = location._get("host").cast()
    let provider = @core.throwable(fn() {
      @core.new(runtime._get("WebsocketProvider"), [
        @core.any(protocol + "//" + host + "/sync"),
        room,
        doc,
        @core.from_entries([
          ("disableBc", @core.any(true)),
          ("connect", @core.any(false)),
        ]),
      ])
    })
    defer {
      dispose_host(provider)
      dispose_host(provider._get("awareness"))
    }
    @core.throwable(fn() {
      provider._get("awareness")._call("setLocalState", [@core.null()])
    })
    |> ignore
    publish_room(provider, doc, project, signal, runtime)
    check_abort(signal)
    @core.throwable(fn() {
      let url = @core.new(global._get("URL"), [location._get("href")])
      url._get("searchParams")._call("set", [@core.any("room"), room]) |> ignore
      url
    })
  })
  |> native_errors
}
