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
fn Room::receive_update(
  self : Room,
  update : @core.Any,
  socket : @core.Any,
) -> Unit {
  let yjs = self.runtime._get("Y")
  yjs._call("decodeUpdate", [update]) |> ignore
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
          yjs._call("applyUpdate", [self.doc, update, socket]) |> ignore
          self.updates += 1
          if self.migrate() || self.updates >= 256 {
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
    let message = @wire.encoder()
    @wire.write_uint(message, 0.0)
    self.runtime._get("sync")._call("writeUpdate", [@core.any(message), bytes])
    |> ignore
    self.broadcast(@wire.to_bytes(message))
  }
}

///|
fn Room::message(self : Room, socket : @core.Any, message : @core.Any) -> Unit {
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
          0.0 =>
            self.runtime
            ._get("sync")
            ._call("readSyncStep1", [
              @core.any(decoder),
              @core.any(reply),
              self.doc,
            ])
            |> ignore
          1.0 | 2.0 => self.receive_update(@wire.read_bytes(decoder), socket)
          _ => @core.throw_error("Unknown sync message")
        }
        if @wire.length(reply) > 1 {
          self.send(socket, @wire.to_bytes(reply))
        }
      }
      1.0 => {
        let previous = attachment(socket)
        let next = @presence.read_presence_update(
          @wire.read_bytes(decoder),
          previous,
        )
        if !@core.is_nullish(next) && !@core.equal(next, previous) {
          self.update_presence(socket, next)
        }
      }
      3.0 => self.send(socket, @presence.presence_message(self.all_presence()))
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
