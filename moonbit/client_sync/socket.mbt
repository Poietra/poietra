///|
priv struct Outbox {
  yjs : @core.Any
  send : (@core.Any) -> Unit
  open : () -> Bool
  interval : () -> Int
  updates : Array[@core.Any]
  mut bytes : Int
  mut timer : @core.Any?
  mut disposed : Bool
}

///|
// Native inheritance/lifecycle only. Queueing and wire decisions live below.
extern "js" fn extend_socket(
  base : @core.Any,
  create : ((@core.Any) -> Unit, () -> Bool) -> Outbox,
  send : (Outbox, @core.Any) -> Unit,
  flush : (Outbox) -> Unit,
  dispose : (Outbox) -> Unit,
) -> @core.Any =
  #|(Base, create, send, flush, dispose) => class extends Base {
  #|  constructor(...args) {
  #|    super(...args);
  #|    this.outbox = create(data => super.send(data), () => this.readyState === 1);
  #|    this.addEventListener('close', () => dispose(this.outbox), { once: true });
  #|  }
  #|  send(data) { send(this.outbox, data); }
  #|  flushDocuments() { flush(this.outbox); }
  #|  close(...args) {
  #|    try { flush(this.outbox); }
  #|    finally { dispose(this.outbox); super.close(...args); }
  #|  }
  #|}

///|
extern "js" fn as_bytes(value : @core.Any) -> Bytes? =
  #|value => value instanceof Uint8Array ? value : undefined

///|
/// y-websocket's public WebSocketPolyfill seam keeps its reconnect, awareness,
/// sync handshake and origin filtering intact. Each connection owns its outbox.
pub fn batched_websocket_class(
  base : @core.Any,
  yjs : @core.Any,
  interval : () -> Int,
) -> @core.Any {
  // Injectable test providers need not have a native WebSocket implementation.
  if @core.is_nullish(base) {
    return base
  }
  extend_socket(
    base,
    fn(send, open) {
      {
        yjs,
        send,
        open,
        interval,
        updates: [],
        bytes: 0,
        timer: None,
        disposed: false,
      }
    },
    Outbox::send,
    Outbox::flush,
    Outbox::dispose,
  )
}

///|
fn Outbox::clear(self : Outbox) -> Unit {
  if self.timer is Some(timer) {
    @core.global_this()._call("clearTimeout", [timer]) |> ignore
    self.timer = None
  }
  self.updates.clear()
  self.bytes = 0
}

///|
fn Outbox::dispose(self : Outbox) -> Unit {
  self.disposed = true
  self.clear()
}

///|
fn Outbox::flush(self : Outbox) -> Unit {
  if self.updates.is_empty() {
    return
  }
  // Offline edits remain in the Y.Doc / IndexedDB and the next sync handshake
  // recovers them. Never send a stale queue on a successor's socket.
  if self.disposed || !(self.open)() {
    self.clear()
    return
  }
  let update = if self.updates.length() == 1 {
    self.updates[0]
  } else {
    self.yjs._call("mergeUpdates", [@core.any(self.updates)])
  }
  let packet = @wire.encoder()
  @wire.write_uint(packet, 0.0)
  @wire.write_uint(packet, 2.0)
  @wire.write_bytes(packet, update)
  // Do not retain a second copy after handing data to native WebSocket.send.
  self.clear()
  (self.send)(@wire.to_bytes(packet))
}

///|
fn update_payload(data : @core.Any) -> @core.Any? {
  guard as_bytes(data) is Some(bytes) &&
    bytes.length() > 2 &&
    bytes[0] == 0 &&
    bytes[1] == 2 else {
    return None
  }
  // Only complete update frames are batched. Leave other/invalid native sends
  // untouched; the server still owns validation.
  @core.throwable(fn() {
    let decoder = @wire.decoder(data)
    @wire.read_uint(decoder) |> ignore
    @wire.read_uint(decoder) |> ignore
    let update = @wire.read_bytes(decoder)
    if (@core.any(decoder)._get("pos").cast() : Int) == bytes.length() {
      Some(update)
    } else {
      None
    }
  }) catch {
    _ => None
  }
}

///|
fn Outbox::send(self : Outbox, data : @core.Any) -> Unit {
  if self.disposed || !(self.open)() {
    self.clear()
    (self.send)(data)
    return
  }
  guard update_payload(data) is Some(update) else {
    // Flush before sync steps, acknowledgments, awareness or other control data.
    self.flush()
    (self.send)(data)
    return
  }
  let interval = (self.interval)().max(0).min(50)
  if interval == 0 {
    self.flush()
    (self.send)(data)
    return
  }
  let size : Int = update._get("byteLength").cast()
  if self.bytes + size > 262144 || self.updates.length() >= 128 {
    self.flush()
  }
  if size >= 262144 {
    (self.send)(data)
    return
  }
  // Match native send's ownership: callers may reuse their buffer immediately.
  self.updates.push(update._call("slice", []))
  self.bytes += size
  if self.timer is None {
    self.timer = Some(
      @core.global_this()._call("setTimeout", [
        @core.any(fn() { self.flush() }),
        @core.any(interval),
      ]),
    )
  }
}
