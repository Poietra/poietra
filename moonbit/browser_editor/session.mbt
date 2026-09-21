///|
priv struct StoreSession {
  store : @core.Any
  listeners : @collection.JsSet[() -> Unit]
  cleanup : Array[() -> Unit]
  mut state : @core.Any
  mut project : @core.Any
  mut peers : FixedArray[@core.Any]
  pending_storage : @collection.JsSet[@core.Any]
  mut connection : @editor.Connection
  mut connection_wait : @core.Any?
  mut local_wait : @core.Any?
  mut local_failed : Bool
  mut transactions_running : Bool
  mut destroyed : Bool
  mut pending_presence : @core.Any?
  mut presence_timer : @core.Any?
  mut peer_timer : @core.Any?
  mut peer_sources : @collection.JsMap[Double, @core.Any]
  mut peer_views : @collection.JsMap[Double, @core.Any]
  mut last_presence : Double
}

///|
fn session(store : @core.Any) -> StoreSession {
  store._get("moon").cast()
}

///|
fn stored_value(kind : String, key : String) -> String? {
  try {
    let value = @core.throwable(fn() {
      @core.global_this()._get(kind)._call("getItem", [@core.any(key)])
    })
    if @core.is_nullish(value) {
      None
    } else {
      Some(value.cast())
    }
  } catch {
    _ => None
  }
}

///|
fn store_value(kind : String, key : String, value : String) -> Unit {
  try
    @core.throwable(fn() {
      @core.global_this()
      ._get(kind)
      ._call("setItem", [@core.any(key), @core.any(value)])
    })
    |> ignore
  catch {
    _ => ()
  }
}

///|
fn cancel_timer(timer : @core.Any?) -> Unit {
  if timer is Some(timer) {
    @core.global_this()._call("clearTimeout", [timer]) |> ignore
  }
}

///|
fn delay(callback : () -> Unit) -> @core.Any {
  @core.global_this()._call("setTimeout", [@core.any(callback), @core.any(8000)])
}

///|
fn StoreSession::publish(self : StoreSession) -> Unit {
  if self.destroyed {
    return
  }
  let undo = self.store._get("undoManager")
  self.state = record([
    ("project", self.project),
    (
      "status",
      @core.any(
        match self.connection.transport {
          Connected => "connected"
          Disconnected => "disconnected"
          Connecting => "connecting"
        },
      ),
    ),
    ("synced", @core.any(self.connection.synced)),
    (
      "localPersistence",
      @core.any(
        match self.connection.persistence {
          Ready => "ready"
          Loading => "loading"
          Unavailable => "unavailable"
        },
      ),
    ),
    (
      "connectionIssue",
      match self.connection.issue {
        Some(issue) => @core.any(issue)
        None => @core.null()
      },
    ),
    ("peers", @core.any(self.peers)),
    ("canUndo", undo._call("canUndo", [])),
    ("canRedo", undo._call("canRedo", [])),
  ])
  self.listeners.forEach(fn(listener) { listener() })
}

///|
fn StoreSession::read_project(self : StoreSession) -> Unit {
  if self.destroyed {
    return
  }
  self.project = @boundary.read_project(
    self.store._get("doc"),
    host(self.store),
  )
  self.connection = { ..self.connection, has_project: truthy(self.project), }
  self.publish()
  self.watch_connection()
}

///|
fn StoreSession::read_peers(self : StoreSession) -> Unit {
  if self.destroyed {
    return
  }
  let states : @collection.JsMap[Double, @core.Any] = self.store
    ._get("provider")
    ._get("awareness")
    ._call("getStates", [])
    .cast()
  let peers = []
  let sources : @collection.JsMap[Double, @core.Any] = @collection.JsMap::new()
  let views : @collection.JsMap[Double, @core.Any] = @collection.JsMap::new()
  states.forEach(fn(data, client) {
    if truthy(data._get("user")) {
      let peer = if self.peer_sources.get(client) is Some(previous) &&
        @core.equal(previous, data) {
        self.peer_views.get(client).unwrap()
      } else {
        merge(
          merge(record([("clientId", @core.any(client))]), data._get("user")),
          data._get("editor"),
        )
      }
      sources.set(client, data) |> ignore
      views.set(client, peer) |> ignore
      peers.push(peer)
    }
  })
  self.peer_sources = sources
  self.peer_views = views
  self.peers = FixedArray::from_array(peers[:])
  self.publish()
}

///|
fn StoreSession::watch_connection(self : StoreSession) -> Unit {
  if self.destroyed {
    return
  }
  if self.connection.transport == Connected &&
    self.connection.synced &&
    self.connection.has_project {
    cancel_timer(self.connection_wait)
    self.connection_wait = None
    if self.connection.issue is Some(_) {
      self.connection = { ..self.connection, issue: None, }
      self.publish()
    }
  } else if self.connection_wait is None {
    // One deadline spans automatic reconnects; repeated connecting events must
    // not leave an unsynced room showing a spinner forever.
    self.connection_wait = Some(
      delay(fn() {
        if self.destroyed {
          return
        }
        self.connection_wait = None
        let message = if self.connection.transport == Connected {
          "サーバーに接続しましたが、同期が完了していません。再接続してください。"
        } else {
          "接続に時間がかかっています。ネットワークを確認して再接続してください。"
        }
        self.connection = { ..self.connection, issue: Some(message), }
        self.publish()
      }),
    )
  }
}

///|
fn StoreSession::on(
  self : StoreSession,
  target : @core.Any,
  event : String,
  callback : @core.Any,
) -> Unit {
  target._call("on", [@core.any(event), callback]) |> ignore
  self.cleanup.push(fn() {
    if @core.typeof_(target._get("off")) == "function" {
      target._call("off", [@core.any(event), callback]) |> ignore
    }
  })
}

///|
fn StoreSession::dispose(self : StoreSession) -> Unit {
  if self.destroyed {
    return
  }
  self.destroyed = true
  cancel_timer(self.peer_timer)
  self.peer_timer = None
  self.peer_sources.clear()
  self.peer_views.clear()
  cancel_timer(self.presence_timer)
  self.presence_timer = None
  self.pending_presence = None
  cancel_timer(self.connection_wait)
  cancel_timer(self.local_wait)
  self.connection_wait = None
  self.local_wait = None
  self.listeners.clear()
  self.pending_storage.forEach(fn(transaction) {
    transaction._set("oncomplete", @core.null())
    transaction._set("onabort", @core.null())
    transaction._set("onerror", @core.null())
  })
  self.pending_storage.clear()
  for i = self.cleanup.length() - 1; i >= 0; i = i - 1 {
    @core.throwable(self.cleanup[i]) catch {
      _ => ()
    }
  }
  self.cleanup.clear()
  // y-websocket does not destroy its socket/intervals when the Doc is destroyed.
  let provider = self.store._get("provider")
  if !@core.is_nullish(provider) &&
    @core.typeof_(provider._get("destroy")) == "function" {
    try
      @core.throwable(fn() { provider._call("destroy", []) }) |> ignore
    catch {
      _ => ()
    }
  }
}

///|
fn StoreSession::local_failure(self : StoreSession) -> Unit {
  if self.destroyed {
    return
  }
  self.local_failed = true
  cancel_timer(self.local_wait)
  self.local_wait = None
  self.connection = { ..self.connection, persistence: Unavailable, }
  self.publish()
}

///|
fn StoreSession::watch_persistence(self : StoreSession) -> Unit {
  self.local_wait = Some(
    delay(fn() {
      if self.destroyed {
        return
      }
      self.local_wait = None
      self.connection = { ..self.connection, persistence: Unavailable, }
      self.publish()
    }),
  )
  let persistence = self.store._get("persistence")
  persistence
  ._get("_db")
  ._call("then", [
    @core.any(fn(db : @core.Any) {
      if self.destroyed {
        return
      }
      let fail = @core.any(fn() { self.local_failure() })
      for event in ["error", "abort", "close"] {
        db._call("addEventListener", [@core.any(event), fail]) |> ignore
        self.cleanup.push(fn() {
          db._call("removeEventListener", [@core.any(event), fail]) |> ignore
        })
      }
    }),
  ])
  ._call("catch", [@core.any(fn(_error : @core.Any) { self.local_failure() })])
  |> ignore
  self.on(
    persistence,
    "synced",
    @core.any(fn() {
      if self.destroyed {
        return
      }
      self.read_project()
      // Wait behind the initial IndexedDB write before reporting durable storage.
      @core.throwable(fn() {
        let transaction = persistence
          ._get("db")
          ._call("transaction", [@core.any("updates"), @core.any("readonly")])
        self.pending_storage.add(transaction) |> ignore
        let release = fn() {
          self.pending_storage.delete(transaction) |> ignore
          transaction._set("oncomplete", @core.null())
          transaction._set("onabort", @core.null())
          transaction._set("onerror", @core.null())
        }
        transaction._set(
          "oncomplete",
          @core.any(fn() {
            release()
            if self.destroyed || self.local_failed {
              return
            }
            cancel_timer(self.local_wait)
            self.local_wait = None
            self.connection = { ..self.connection, persistence: Ready, }
            self.publish()
          }),
        )
        let fail = @core.any(fn() {
          release()
          self.local_failure()
        })
        transaction._set("onabort", fail)
        transaction._set("onerror", fail)
      }) catch {
        _ => self.local_failure()
      }
    }),
  )
}

///|
fn StoreSession::schedule_peers(self : StoreSession) -> Unit {
  if self.destroyed || self.peer_timer is Some(_) {
    return
  }
  self.peer_timer = Some(
    @core.global_this()._call("setTimeout", [
      @core.any(fn() {
        self.peer_timer = None
        self.read_peers()
      }),
      @core.any(16),
    ]),
  )
}
