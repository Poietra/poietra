///|
priv struct Room {
  ctx : @core.Any
  env : @core.Any
  runtime : @core.Any
  doc : @core.Any
  sql : @cf.SqlStorage
  storage : @core.Any
  assets : @core.Any
  promoting : Set[String]
  mut updates : Int
  mut journal_bytes : Int
  connections : @collection.JsMap[@core.Any, @core.Any]
  owners : @collection.JsMap[Double, @core.Any]
  mut restored_connections : Bool
  mut fanout : @sync.Fanout?
  inbound : Array[@core.Any]
  mut inbound_bytes : Int
  mut inbound_timer : @core.Any?
}

///|
fn string(value : @core.Any, key : String) -> String {
  value._get(key).cast()
}

///|
fn now() -> Double {
  @core.global_this()._get("Date")._call("now", []).cast()
}

///|
fn fail(message : String) -> Unit raise {
  @core.throwable(fn() { @core.throw_error(message) })
}

///|
fn response(
  body : @core.Any,
  status? : Int = 200,
  headers? : @core.Any = @core.new_object(),
) -> @core.Any {
  @core.new(@core.global_this()._get("Response"), [
    body,
    @core.from_entries([("status", @core.any(status)), ("headers", headers)]),
  ])
}

///|
fn json(value : @core.Any, status? : Int = 200) -> @core.Any {
  @core.global_this()
  ._get("Response")
  ._call("json", [
    value,
    @core.from_entries([
      ("status", @core.any(status)),
      (
        "headers",
        @http.headers_object([
          ("Cache-Control", "no-store"),
          ("X-Robots-Tag", "noindex"),
        ]),
      ),
    ]),
  ])
}

///|
fn error_response(message : String, status : Int) -> @core.Any {
  json(@core.from_entries([("error", @core.any(message))]), status~)
}

///|
fn Room::restore_connections(self : Room) -> Unit {
  if self.restored_connections {
    return
  }
  self.restored_connections = true
  for
    socket in (
      self.ctx._call("getWebSockets", []).cast() : FixedArray[@core.Any]) {
    if !@core.equal(socket._get("readyState"), @core.any(1)) {
      continue
    }
    let value = attachment(socket)
    self.connections.set(socket, value) |> ignore
    if !@core.is_nullish(value) && !@core.is_nullish(value._get("state")) {
      self.owners.set(value._get("clientId").cast(), socket) |> ignore
    }
  }
}

///|
fn Room::send(_self : Room, socket : @core.Any, bytes : @core.Any) -> Unit {
  let connection : @websocket.WebSocket = socket.cast()
  if connection.readyState != 1 {
    return
  }
  (@core.throwable(fn() { connection.send_uint8array(bytes.cast()) }) |> ignore) catch {
    _ =>
      // A failed connection must resynchronize instead of silently missing edits.
      (@core.throwable(fn() {
        socket._call("close", [@core.any(1011), @core.any("Resynchronize")])
      })
      |> ignore) catch {
        _ => ()
      }
  }
}

///|
fn Room::broadcast(self : Room, bytes : @core.Any) -> Unit {
  self.connections.forEach(fn(_, socket) { self.send(socket, bytes) })
}

///|
fn attachment(socket : @core.Any) -> @core.Any {
  socket._call("deserializeAttachment", [])
}

///|
fn attach(socket : @core.Any, state : @core.Any) -> Unit {
  socket._call("serializeAttachment", [state]) |> ignore
}

///|
fn absent(presence : @core.Any) -> @core.Any {
  @core.from_entries([
    ("clientId", presence._get("clientId")),
    ("clock", presence._get("clock")),
    ("state", @core.null()),
  ])
}

///|
fn Room::all_presence(self : Room) -> FixedArray[@core.Any] {
  let values = []
  self.connections.forEach(fn(value, _) {
    if !@core.is_nullish(value) && !@core.is_nullish(value._get("state")) {
      values.push(value)
    }
  })
  FixedArray::from_array(values[:])
}

///|
fn Room::remember(self : Room, socket : @core.Any, value : @core.Any) -> Unit {
  attach(socket, value)
  self.connections.set(socket, value) |> ignore
}

///|
fn Room::update_presence(
  self : Room,
  socket : @core.Any,
  next : @core.Any,
) -> Unit {
  let id : Double = next._get("clientId").cast()
  if self.owners.get(id) is Some(other) && !@core.equal(socket, other) {
    let previous = self.connections.get(other).unwrap()
    let old : Double = previous._get("clock").cast()
    let clock : Double = next._get("clock").cast()
    if old > clock ||
      (old == clock && !@core.is_nullish(previous._get("state"))) {
      return
    }
    self.remember(other, absent(previous))
    // Release the admission slot immediately; a half-open predecessor must not
    // consume reconnect headroom or publish a later queued presence frame.
    self.connections.delete(other) |> ignore
    (@core.throwable(fn() {
      other._call("close", [@core.any(1000), @core.any("Connection replaced")])
    })
    |> ignore) catch {
      _ => ()
    }
  }
  self.remember(socket, next)
  self.owners.set(id, socket) |> ignore
  self.fanout.unwrap().presence(next)
}

///|
fn Room::remove_presence(self : Room, socket : @core.Any) -> Unit {
  self.restore_connections()
  // A late close from a replaced socket cannot remove its successor's state.
  let presence = self.connections
    .get(socket)
    .unwrap_or_else(fn() { attachment(socket) })
  self.connections.delete(socket) |> ignore
  if !@core.is_nullish(presence) {
    let id : Double = presence._get("clientId").cast()
    let owner = self.owners.get(id)
    if owner is None || (owner is Some(owner) && @core.equal(owner, socket)) {
      self.owners.delete(id) |> ignore
      if !@core.is_nullish(presence._get("state")) {
        self.fanout.unwrap().presence(absent(presence))
      }
    }
  }
}

///|
fn asset_value(value : @core.Any) -> @core.Any raise {
  @core.throwable(fn() { @delivery.asset_value(value) })
}

///|
fn Room::send_presence(self : Room, socket : @core.Any) -> Unit {
  for packet in @presence.presence_messages(self.all_presence()) {
    self.send(socket, packet)
  }
}
