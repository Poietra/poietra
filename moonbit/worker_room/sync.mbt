///|
fn Room::compact(self : Room) -> Unit {
  self.storage._call("transactionSync", [
    @core.any(fn() {
      self.sql.exec1(
        "INSERT OR REPLACE INTO snapshot (id, data) VALUES (1, ?)",
        self.runtime._get("Y")._call("encodeStateAsUpdate", [self.doc]),
      )
      |> ignore
      self.sql.exec_raw("DELETE FROM updates") |> ignore
    }),
  ])
  |> ignore
  self.updates = 0
  self.journal_bytes = 0
}

///|
fn Room::migrate(self : Room) -> Bool {
  let audio = @boundary.ensure_scene_audio_tracks(
    self.doc,
    self.runtime._get("Y"),
  )
  let animations = @boundary.ensure_scene_animation_tracks(
    self.doc,
    self.runtime._get("Y"),
  )
  audio || animations
}

///|
fn Room::receive_update(self : Room, update : @core.Any) -> Unit {
  let yjs = self.runtime._get("Y")
  let outgoing = []
  let collect = fn(bytes : @core.Any) { outgoing.push(bytes) }
  self.doc._call("on", [@core.any("update"), @core.any(collect)]) |> ignore
  defer self.doc._call("off", [@core.any("update"), @core.any(collect)])
    |> ignore
  try
    @core.throwable(fn() {
      self.storage._call("transactionSync", [
        @core.any(fn() {
          // Persist even updates waiting for missing Yjs dependencies, before broadcasting.
          self.sql.exec1("INSERT INTO updates (data) VALUES (?)", update)
          |> ignore
          yjs._call("applyUpdate", [self.doc, update, @core.null()]) |> ignore
          self.updates += 1
          self.journal_bytes += (update._get("byteLength").cast() : Int)
          if self.migrate() ||
            self.updates >= 256 ||
            self.journal_bytes >= 4194304 {
            self.compact()
          }
        }),
      ])
    })
    |> ignore
  catch {
    _ => {
      // In-memory state cannot survive a rolled-back journal. Reconnect and restore.
      self.ctx._call("abort", [@core.any("Project update could not be stored")])
      |> ignore
      return
    }
  }
  for bytes in outgoing {
    self.fanout.unwrap().document(bytes)
  }
}

///|
fn Room::message(self : Room, socket : @core.Any, message : @core.Any) -> Unit {
  self.restore_connections()
  if !self.connections.has(socket) {
    return
  }
  if @core.typeof_(message) == "string" ||
    (message._get("byteLength").cast() : Double) > 2097152.0 {
    socket._call("close", [@core.any(1009), @core.any("Invalid update size")])
    |> ignore
    return
  }
  @core.throwable(fn() {
    let bytes = @buffer.Uint8Array::from_array_buffer(message.cast())
    let decoder = @wire.decoder(bytes.as_any())
    match @wire.read_uint(decoder) {
      0.0 => {
        let reply = @wire.encoder()
        @wire.write_uint(reply, 0.0)
        match @wire.read_uint(decoder) {
          0.0 => {
            // Ordered sync replies acknowledge only already persisted input.
            self.flush_inbound()
            self.runtime
            ._get("sync")
            ._call("readSyncStep1", [
              @core.any(decoder),
              @core.any(reply),
              self.doc,
            ])
            |> ignore
          }
          1.0 | 2.0 => self.queue_update(@wire.read_bytes(decoder))
          _ => @core.throw_error("Unknown sync message")
        }
        if @wire.length(reply) > 1 {
          self.send(socket, @wire.to_bytes(reply))
        }
      }
      1.0 => {
        let previous = self.connections.get(socket).unwrap_or(@core.null())
        let next = @presence.read_presence_update(
          @wire.read_bytes(decoder),
          previous,
        )
        if !@core.is_nullish(next) && !@core.equal(next, previous) {
          self.update_presence(socket, next)
        }
      }
      3.0 => self.send_presence(socket)
      _ => ()
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
fn Room::queue_update(self : Room, update : @core.Any) -> Unit {
  // Reject malformed input on its own socket before it enters a shared batch.
  self.runtime._get("Y")._call("decodeUpdate", [update]) |> ignore
  let bytes : Int = update._get("byteLength").cast()
  if self.inbound_bytes + bytes > 262144 || self.inbound.length() >= 128 {
    self.flush_inbound()
  }
  self.inbound.push(update)
  self.inbound_bytes += bytes
  if self.inbound_bytes >= 262144 {
    self.flush_inbound()
  } else if self.inbound_timer is None {
    self.inbound_timer = Some(
      @core.global_this()._call("setTimeout", [
        @core.any(fn() { self.flush_inbound() }),
        @core.any(if self.connections.size() <= 32 { 0 } else { 10 }),
      ]),
    )
  }
}

///|
fn Room::flush_inbound(self : Room) -> Unit {
  if self.inbound_timer is Some(timer) {
    @core.global_this()._call("clearTimeout", [timer]) |> ignore
  }
  self.inbound_timer = None
  if self.inbound.is_empty() {
    return
  }
  let count = self.inbound.length()
  let update = if count == 1 {
    self.inbound[0]
  } else {
    self.runtime
    ._get("Y")
    ._call("mergeUpdates", [@core.any(FixedArray::from_array(self.inbound[:]))])
  }
  self.inbound.clear()
  self.inbound_bytes = 0
  // mergeUpdates retains unresolved dependencies. Nothing is broadcast or
  // acknowledged until this lossless batch has entered the durable journal.
  self.receive_update(update)
}
