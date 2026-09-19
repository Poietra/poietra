///|
fn initialize_store(store : @core.Any, room : String) -> Unit {
  let runtime = store._get("runtime")
  let global = @core.global_this()
  let doc = @core.new(host(store)._get("Doc"), [])
  store._set("doc", doc)
  let state : StoreSession = {
    store,
    listeners: @collection.JsSet::new(),
    cleanup: [],
    state: @core.undefined(),
    project: @core.null(),
    peers: [],
    pending_storage: @collection.JsSet::new(),
    connection: {
      transport: Connecting,
      synced: false,
      has_project: false,
      persistence: Loading,
      issue: None,
    },
    connection_wait: None,
    local_wait: None,
    local_failed: false,
    transactions_running: false,
    destroyed: false,
  }
  store._set("moon", @core.any(state))
  let random = fn() -> String {
    global._get("crypto")._call("randomUUID", []).cast()
  }
  let author = match stored_value("sessionStorage", "poietra-chat-author") {
    Some(id) if !id.is_empty() => id
    _ => random()
  }
  store._set("chatAuthorId", @core.any(author))
  store_value("sessionStorage", "poietra-chat-author", author)
  let colors : FixedArray[String] = runtime._get("colors").cast()
  let client = number(doc._get("clientID"))
  let color = colors[(client % colors.length().to_double()).to_int()]
  let client_name = global._call("String", [doc._get("clientID")])
  let suffix : String = client_name._call("slice", [@core.any(-3)]).cast()
  let name = match stored_value("localStorage", "poietra-user-name") {
    Some(name) if !name.is_empty() => name
    _ => "Guest " + suffix
  }
  store._set("color", @core.any(color))
  store._set("userName", @core.any(name))
  store._set("chat", @core.new(runtime._get("RoomChat"), [doc]))
  state.on(
    doc,
    "beforeAllTransactions",
    @core.any(fn() { state.transactions_running = true }),
  )
  state.on(
    doc,
    "afterAllTransactions",
    @core.any(fn() { state.transactions_running = false }),
  )
  let undo = @core.new(runtime._get("EditorUndoManager"), [doc])
  store._set("undoManager", undo)
  store._set(
    "persistence",
    @core.new(runtime._get("IndexeddbPersistence"), [
      @core.any("poietra-" + room),
      doc,
    ]),
  )
  let location = global._get("location")
  let protocol = if @core.equal(location._get("protocol"), @core.any("https:")) {
    "wss:"
  } else {
    "ws:"
  }
  let url = protocol + "//" + (location._get("host").cast() : String) + "/sync"
  let provider = @core.new(runtime._get("WebsocketProvider"), [
    @core.any(url),
    @core.any(room),
    doc,
    record([("disableBc", @core.any(true))]),
  ])
  store._set("provider", provider)
  let awareness = provider._get("awareness")
  awareness._call("setLocalStateField", [
    @core.any("user"),
    record([("name", @core.any(name)), ("color", @core.any(color))]),
  ])
  |> ignore
  state.on(
    provider,
    "status",
    @core.any(fn(event : @core.Any) {
      if state.destroyed {
        return
      }
      let transport = match (event._get("status").cast() : String) {
        "connected" => @editor.Connected
        "disconnected" => Disconnected
        _ => Connecting
      }
      if transport == Connected {
        awareness._call("setLocalState", [awareness._call("getLocalState", [])])
        |> ignore
      }
      state.connection = {
        ..state.connection,
        transport,
        synced: transport == Connected && state.connection.synced,
      }
      state.publish()
      state.watch_connection()
    }),
  )
  state.on(
    provider,
    "sync",
    @core.any(fn(synced : Bool) {
      if state.destroyed {
        return
      }
      state.connection = { ..state.connection, synced, }
      state.publish()
      state.watch_connection()
    }),
  )
  for
    (event, message, disconnected) in [
      (
        "connection-close", "サーバーとの接続が切れました。自動で再接続を試みています。",
        true,
      ),
      (
        "connection-error", "サーバーに接続できません。ネットワークを確認して再接続してください。",
        false,
      ),
      (
        "closed", "サーバーが接続を終了しました。再接続してください。続く場合は共有リンクを確認してください。",
        true,
      ),
    ] {
    state.on(
      provider,
      event,
      @core.any(fn() {
        if state.destroyed {
          return
        }
        state.connection = {
          ..state.connection,
          issue: Some(message),
          transport: if disconnected {
            Disconnected
          } else {
            state.connection.transport
          },
          synced: !disconnected && state.connection.synced,
        }
        state.publish()
      }),
    )
  }
  let root = doc._call("getMap", [@core.any("project")])
  let observe = @core.any(fn() { state.read_project() })
  root._call("observeDeep", [observe]) |> ignore
  state.cleanup.push(fn() { root._call("unobserveDeep", [observe]) |> ignore })
  state.on(awareness, "change", @core.any(fn() { state.read_peers() }))
  for
    event in [
      "stack-item-added", "stack-item-popped", "stack-cleared", "stack-item-updated",
    ] {
    state.on(undo, event, @core.any(fn() { state.publish() }))
  }
  state.watch_persistence()
  state.on(doc, "destroy", @core.any(fn() { state.dispose() }))
  state.read_peers()
  state.watch_connection()
}

///|
pub fn create_store(store : @core.Any, room : String) -> Unit {
  let result = try {
    @core.throwable(fn() { initialize_store(store, room) })
    Ok(())
  } catch {
    error => Err(error)
  }
  if result is Err(error) {
    if !@core.is_nullish(store._get("moon")) {
      session(store).dispose()
    }
    let doc = store._get("doc")
    if !@core.is_nullish(doc) {
      try @core.throwable(fn() { doc._call("destroy", []) }) |> ignore catch {
        _ => ()
      }
    }
    @core.throw_(native_error(error))
  }
}

///|
pub fn subscribe(store : @core.Any, listener : () -> Unit) -> () -> Unit {
  let state = session(store)
  if !state.destroyed {
    state.listeners.add(listener) |> ignore
  }
  fn() { state.listeners.delete(listener) |> ignore }
}

///|
pub fn snapshot(store : @core.Any) -> @core.Any {
  session(store).state
}

///|
pub fn retry_connection(store : @core.Any) -> Unit {
  let state = session(store)
  if state.destroyed {
    return
  }
  cancel_timer(state.connection_wait)
  state.connection_wait = None
  let provider = store._get("provider")
  provider._call("disconnect", []) |> ignore
  state.connection = {
    ..state.connection,
    transport: Connecting,
    synced: false,
    issue: None,
  }
  state.publish()
  provider._call("connect", []) |> ignore
  state.watch_connection()
}

///|
pub fn project(store : @core.Any) -> @core.Any {
  let cached = store._get("moon")
  let value = if !@core.is_nullish(cached) &&
    !session(store).transactions_running &&
    truthy(session(store).project) {
    session(store).project
  } else {
    @boundary.read_project(store._get("doc"), host(store))
  }
  if !truthy(value) {
    @core.throw_error("Project is loading")
  }
  value
}

///|
pub fn scene(store : @core.Any, id : String) -> @core.Any {
  let value = project(store)._get("scenes")._get(id)
  if !truthy(value) {
    @core.throw_error("Scene no longer exists")
  }
  value
}

///|
pub fn set_name(store : @core.Any, name : String) -> Unit {
  let edited = slice_text(name.trim().to_owned(), 40)
  let name = if edited.is_empty() {
    store._get("userName").cast()
  } else {
    edited
  }
  store._set("userName", @core.any(name))
  store_value("localStorage", "poietra-user-name", name)
  store
  ._get("provider")
  ._get("awareness")
  ._call("setLocalStateField", [
    @core.any("user"),
    record([("name", @core.any(name)), ("color", store._get("color"))]),
  ])
  |> ignore
}

///|
pub fn presence(store : @core.Any, patch : @core.Any) -> Unit {
  let awareness = store._get("provider")._get("awareness")
  let current = awareness._call("getLocalState", [])
  let previous = if @core.is_nullish(current) {
    @core.undefined()
  } else {
    current._get("editor")
  }
  awareness._call("setLocalStateField", [
    @core.any("editor"),
    merge(previous, patch),
  ])
  |> ignore
}

///|
pub fn current_room() -> String {
  let global = @core.global_this()
  let url = @core.new(global._get("URL"), [global._get("location")._get("href")])
  let query = url._get("searchParams")
  let value = query._call("get", [@core.any("room")])
  let room = if !@core.is_nullish(value) && @editor.valid_room_id(value.cast()) {
    value.cast()
  } else {
    let room = match stored_value("localStorage", "poietra-last-room") {
      Some(room) if @editor.valid_room_id(room) => room
      _ => global._get("crypto")._call("randomUUID", []).cast()
    }
    query._call("set", [@core.any("room"), @core.any(room)]) |> ignore
    global
    ._get("history")
    ._call("replaceState", [@core.null(), @core.any(""), url])
    |> ignore
    room
  }
  store_value("localStorage", "poietra-last-room", room)
  room
}
