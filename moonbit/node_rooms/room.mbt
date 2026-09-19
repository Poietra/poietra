///|
priv struct Room {
  id : String
  filename : String
  host : @core.Any
  doc : @core.Any
  awareness : @core.Any
  connections : @collection.JsMap[@core.Any, @collection.JsSet[Double]]
  presence : @collection.JsMap[@core.Any, @core.Any]
  mut timer : @core.Any?
  mut disposed : Bool
  mut ai_busy : Bool
  mut ai_last_request : Double
}

///|
fn Room::persist(self : Room) -> Bool {
  if self.disposed {
    return true
  }
  try {
    let temporary = self.filename + ".tmp"
    @core.throwable(fn() {
      write_file(
        temporary,
        self.host._get("Y")._call("encodeStateAsUpdate", [self.doc]),
        @core.from_entries([("mode", @core.any(384))]),
      )
    })
    @fs.rename_sync(temporary, self.filename)
    true
  } catch {
    error => {
      let native = native_error(error)
      let message = native._get("message")
      @core.global_this()
      ._get("console")
      ._call("error", [
        @core.any("Could not save project:"),
        if @core.typeof_(message) == "string" {
          message
        } else {
          @core.any("Storage error")
        },
      ])
      |> ignore
      false
    }
  }
}

///|
fn Room::schedule_persist(self : Room) -> Unit {
  if self.timer is None && !self.disposed {
    self.timer = Some(
      @core.global_this()._call("setTimeout", [
        @core.any(fn() {
          self.timer = None
          self.persist() |> ignore
        }),
        @core.any(200),
      ]),
    )
  }
}

///|
fn Room::dispose(self : Room) -> Bool {
  if self.disposed {
    return true
  }
  if self.connections.size() > 0 || self.ai_busy || !self.persist() {
    return false
  }
  self.disposed = true
  if self.timer is Some(timer) {
    @core.global_this()._call("clearTimeout", [timer]) |> ignore
  }
  self.timer = None
  self.awareness._call("destroy", []) |> ignore
  self.doc._call("destroy", []) |> ignore
  true
}

///|
fn send(socket : @core.Any, message : @core.Any) -> Unit {
  if @core.equal(socket._get("readyState"), @core.any(1)) {
    // A failed peer must not interrupt delivery or persistence for other peers.
    try
      @core.throwable(fn() { socket._call("send", [message]) }) |> ignore
    catch {
      _ => ()
    }
  }
}

///|
fn Room::broadcast(self : Room, message : @core.Any) -> Unit {
  self.connections.forEach(fn(_, socket) { send(socket, message) })
}

///|
fn Room::migrate(self : Room) -> Unit {
  let yjs = self.host._get("Y")
  @boundary.ensure_scene_audio_tracks(self.doc, yjs) |> ignore
  @boundary.ensure_scene_animation_tracks(self.doc, yjs) |> ignore
}

///|
fn Room::awareness_message(self : Room) -> @core.Any {
  let states : @collection.JsMap[Double, @core.Any] = self.awareness
    ._call("getStates", [])
    .cast()
  let clients = []
  states.forEach(fn(_, id) { clients.push(@core.any(id)) })
  let message = @wire.encoder()
  @wire.write_uint(message, 1.0)
  @wire.write_bytes(
    message,
    self.host
    ._get("awareness")
    ._call("encodeAwarenessUpdate", [self.awareness, array(clients)]),
  )
  @wire.to_bytes(message)
}

///|
fn Room::update_presence(
  self : Room,
  socket : @core.Any,
  next : @core.Any,
) -> Unit {
  let client : Double = next._get("clientId").cast()
  let clock : Double = next._get("clock").cast()
  let owners = []
  let stale = Ref(false)
  self.presence.forEach(fn(previous, other) {
    if !@core.equal(other, socket) &&
      @core.equal(previous._get("clientId"), @core.any(client)) {
      owners.push((other, previous))
      let old_clock : Double = previous._get("clock").cast()
      if old_clock > clock ||
        (old_clock == clock && !@core.is_null(previous._get("state"))) {
        stale.val = true
      }
    }
  })
  if stale.val {
    return
  }
  for (other, previous) in owners {
    self.presence.set(
      other,
      @core.from_entries([
        ("clientId", previous._get("clientId")),
        ("clock", previous._get("clock")),
        ("state", @core.null()),
      ]),
    )
    |> ignore
    if self.connections.get(other) is Some(owned) {
      owned.delete(client) |> ignore
    }
  }
  self.presence.set(socket, next) |> ignore
  let clean = @wire.decoder(@presence.presence_message([next]))
  @wire.read_uint(clean) |> ignore
  self.host
  ._get("awareness")
  ._call("applyAwarenessUpdate", [
    self.awareness,
    @wire.read_bytes(clean),
    socket,
  ])
  |> ignore
}

///|
fn Room::message(self : Room, socket : @core.Any, data : @core.Any) -> Unit {
  if self.disposed {
    return
  }
  @core.throwable(fn() {
    let decoder = @wire.decoder(bytes(data))
    let kind = @wire.read_uint(decoder)
    if kind == 0.0 {
      let reply = @wire.encoder()
      @wire.write_uint(reply, 0.0)
      let sync_type : Double = self.host
        ._get("sync")
        ._call("readSyncMessage", [
          @core.any(decoder),
          @core.any(reply),
          self.doc,
          socket,
        ])
        .cast()
      self.migrate()
      // Pending Yjs dependencies do not emit an update yet, but must be saved.
      if sync_type == 1.0 || sync_type == 2.0 {
        self.schedule_persist()
      }
      if @wire.length(reply) > 1 {
        send(socket, @wire.to_bytes(reply))
      }
    } else if kind == 1.0 {
      let previous = self.presence.get(socket).unwrap_or(@core.null())
      let next = @presence.read_presence_update(
        @wire.read_bytes(decoder),
        previous,
      )
      if !@core.is_nullish(next) && !@core.equal(next, previous) {
        self.update_presence(socket, next)
      }
    } else if kind == 3.0 {
      send(socket, self.awareness_message())
    }
  }) catch {
    _ =>
      socket._call("close", [
        @core.any(1003),
        @core.any("Invalid document update"),
      ])
      |> ignore
  }
}

///|
fn Room::connect(self : Room, socket : @core.Any) -> Unit {
  if self.disposed {
    socket._call("close", []) |> ignore
    return
  }
  self.connections.set(socket, @collection.JsSet::new()) |> ignore
  let encoder = @wire.encoder()
  @wire.write_uint(encoder, 0.0)
  self.host._get("sync")._call("writeSyncStep1", [@core.any(encoder), self.doc])
  |> ignore
  send(socket, @wire.to_bytes(encoder))
  let states : @collection.JsMap[Double, @core.Any] = self.awareness
    ._call("getStates", [])
    .cast()
  if states.size() > 0 {
    send(socket, self.awareness_message())
  }
  socket._call("on", [
    @core.any("message"),
    @core.any(fn(data : @core.Any) { self.message(socket, data) }),
  ])
  |> ignore
  socket._call("on", [
    @core.any("close"),
    @core.any(fn() {
      let clients = match self.connections.get(socket) {
        Some(owned) => set_values(owned)
        None => array([])
      }
      self.host
      ._get("awareness")
      ._call("removeAwarenessStates", [self.awareness, clients, @core.null()])
      |> ignore
      self.connections.delete(socket) |> ignore
      self.presence.delete(socket) |> ignore
      self.persist() |> ignore
    }),
  ])
  |> ignore
  socket._call("on", [
    @core.any("error"),
    @core.any(fn() { socket._call("close", []) |> ignore }),
  ])
  |> ignore
}
