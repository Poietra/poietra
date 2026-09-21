///|
/// Only already accepted updates enter this queue. Durable hosts persist first.
/// Documents merge losslessly; ephemeral presence keeps the newest clock per ID.
/// Short one-shot timers allow the room to hibernate again when traffic stops.
pub struct Fanout {
  yjs : @core.Any
  sync : @core.Any
  send : (@core.Any) -> Unit
  peers : () -> Int
  documents : Array[@core.Any]
  presence : @collection.JsMap[Double, @core.Any]
  mut bytes : Int
  mut document_timer : @core.Any?
  mut presence_timer : @core.Any?
}

///|
pub fn fanout(
  yjs : @core.Any,
  sync : @core.Any,
  send : (@core.Any) -> Unit,
  peers : () -> Int,
) -> Fanout {
  {
    yjs,
    sync,
    send,
    peers,
    documents: [],
    presence: @collection.JsMap::new(),
    bytes: 0,
    document_timer: None,
    presence_timer: None,
  }
}

///|
fn cancel(timer : @core.Any?) -> Unit {
  if timer is Some(timer) {
    @core.global_this()._call("clearTimeout", [timer]) |> ignore
  }
}

///|
fn later(callback : () -> Unit, milliseconds : Int) -> @core.Any {
  @core.global_this()._call("setTimeout", [
    @core.any(callback),
    @core.any(milliseconds),
  ])
}

///|
pub fn Fanout::flush_documents(self : Fanout) -> Unit {
  cancel(self.document_timer)
  self.document_timer = None
  if self.documents.is_empty() {
    return
  }
  let update = if self.documents.length() == 1 {
    self.documents[0]
  } else {
    self.yjs._call("mergeUpdates", [
      @core.any(FixedArray::from_array(self.documents[:])),
    ])
  }
  self.documents.clear()
  self.bytes = 0
  let message = @wire.encoder()
  @wire.write_uint(message, 0.0)
  self.sync._call("writeUpdate", [@core.any(message), update]) |> ignore
  (self.send)(@wire.to_bytes(message))
}

///|
pub fn Fanout::document(self : Fanout, update : @core.Any) -> Unit {
  let bytes : Int = update._get("byteLength").cast()
  // Bound retained input, including bursts and large portable imports. Flush
  // before adding: separate valid messages must not become an oversized one.
  if self.bytes + bytes > 262144 || self.documents.length() >= 128 {
    self.flush_documents()
  }
  self.documents.push(update)
  self.bytes += bytes
  if self.bytes >= 262144 {
    self.flush_documents()
  } else if self.document_timer is None {
    self.document_timer = Some(
      later(
        fn() { self.flush_documents() },
        if (self.peers)() <= 32 {
          16
        } else {
          50
        },
      ),
    )
  }
}

///|
pub fn Fanout::flush_presence(self : Fanout) -> Unit {
  cancel(self.presence_timer)
  self.presence_timer = None
  if self.presence.size() == 0 {
    return
  }
  let entries = []
  self.presence.forEach(fn(entry, _) { entries.push(entry) })
  self.presence.clear()
  for packet in @presence.presence_messages(FixedArray::from_array(entries[:])) {
    (self.send)(packet)
  }
}

///|
pub fn Fanout::presence(self : Fanout, entry : @core.Any) -> Unit {
  self.presence.set(entry._get("clientId").cast(), entry) |> ignore
  if self.presence_timer is None {
    self.presence_timer = Some(later(fn() { self.flush_presence() }, 100))
  }
}

///|
pub fn Fanout::dispose(self : Fanout) -> Unit {
  cancel(self.document_timer)
  cancel(self.presence_timer)
  self.document_timer = None
  self.presence_timer = None
  self.documents.clear()
  self.presence.clear()
  self.bytes = 0
}
