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
fn Room::sockets(self : Room) -> Array[@core.Any] {
  (self.ctx._call("getWebSockets", []).cast() : FixedArray[@core.Any])
  .iter()
  .to_array()
}

///|
fn Room::send(_self : Room, socket : @core.Any, bytes : @core.Any) -> Unit {
  (@core.throwable(fn() { socket._call("send", [bytes]) }) |> ignore) catch {
    _ => ()
  }
}

///|
fn Room::broadcast(self : Room, bytes : @core.Any) -> Unit {
  for socket in self.sockets() {
    self.send(socket, bytes)
  }
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
  let values = self
    .sockets()
    .map(attachment)
    .filter(fn(value) {
      !@core.is_nullish(value) && !@core.is_nullish(value._get("state"))
    })
  FixedArray::from_array(values[:])
}

///|
fn Room::update_presence(
  self : Room,
  socket : @core.Any,
  next : @core.Any,
) -> Unit {
  let previous_owners = self
    .sockets()
    .filter(fn(other) {
      let previous = attachment(other)
      !@core.equal(socket, other) &&
      !@core.is_nullish(previous) &&
      @core.equal(previous._get("clientId"), next._get("clientId"))
    })
  let clock : Double = next._get("clock").cast()
  if previous_owners.any(fn(other) {
      let previous = attachment(other)
      let old : Double = previous._get("clock").cast()
      old > clock || (old == clock && !@core.is_nullish(previous._get("state")))
    }) {
    return
  }
  for other in previous_owners {
    attach(other, absent(attachment(other)))
  }
  attach(socket, next)
  self.broadcast(@presence.presence_message([next]))
}

///|
fn Room::remove_presence(self : Room, socket : @core.Any) -> Unit {
  let presence = attachment(socket)
  if !@core.is_nullish(presence) && !@core.is_nullish(presence._get("state")) {
    let next = absent(presence)
    attach(socket, next)
    self.broadcast(@presence.presence_message([next]))
  }
}

///|
fn asset_value(value : @core.Any) -> @core.Any raise {
  @core.throwable(fn() { @delivery.asset_value(value) })
}
