///|
fn create_room(
  id : String,
  directory : String,
  host : @core.Any,
) -> @core.Any raise {
  let yjs = host._get("Y")
  let doc = @core.throwable(fn() { @core.new(yjs._get("Doc"), []) })
  errdefer doc._call("destroy", []) |> ignore
  let awareness = @core.throwable(fn() {
    @core.new(host._get("awareness")._get("Awareness"), [doc])
  })
  let room : Room = {
    id,
    filename: resolve_path(directory, id + ".yjs"),
    host,
    doc,
    awareness,
    connections: @collection.JsMap::new(),
    presence: @collection.JsMap::new(),
    timer: None,
    disposed: false,
    ai_busy: false,
    ai_last_request: 0.0,
  }
  awareness._call("setLocalState", [@core.null()]) |> ignore
  if @fs.exists_sync(room.filename) {
    let data = @fs.read_file_as_buffer(room.filename)
    @core.throwable(fn() { yjs._call("applyUpdate", [doc, @core.any(data)]) })
    |> ignore
  } else {
    @boundary.initialize_document(doc, @boundary.make_demo_project(), yjs)
  }
  room.migrate()
  doc._call("on", [
    @core.any("update"),
    @core.any(fn(update : @core.Any) {
      let encoder = @wire.encoder()
      @wire.write_uint(encoder, 0.0)
      host._get("sync")._call("writeUpdate", [@core.any(encoder), update])
      |> ignore
      room.broadcast(@wire.to_bytes(encoder))
      room.schedule_persist()
    }),
  ])
  |> ignore
  doc._call("on", [
    @core.any("destroy"),
    @core.any(fn() {
      room.disposed = true
      if room.timer is Some(timer) {
        @core.global_this()._call("clearTimeout", [timer]) |> ignore
      }
      room.timer = None
    }),
  ])
  |> ignore
  awareness._call("on", [
    @core.any("update"),
    @core.any(fn(changed : @core.Any, socket : @core.Any) {
      let owned = room.connections.get(socket)
      let clients = []
      for key in ["added", "updated", "removed"] {
        for client in (changed._get(key).cast() : FixedArray[Double]) {
          clients.push(@core.any(client))
          if owned is Some(owned) {
            if key == "removed" {
              owned.delete(client) |> ignore
            } else {
              owned.add(client) |> ignore
            }
          }
        }
      }
      let encoder = @wire.encoder()
      @wire.write_uint(encoder, 1.0)
      @wire.write_bytes(
        encoder,
        host
        ._get("awareness")
        ._call("encodeAwarenessUpdate", [awareness, array(clients)]),
      )
      room.broadcast(@wire.to_bytes(encoder))
    }),
  ])
  |> ignore
  room.persist() |> ignore
  let api = @core.from_entries([
    ("id", @core.any(room.id)),
    ("doc", doc),
    ("awareness", awareness),
    ("connections", room.connections.to_any()),
    ("persist", @core.any(fn() { room.persist() })),
    ("dispose", @core.any(fn() { room.dispose() })),
    ("connect", @core.any(fn(socket : @core.Any) { room.connect(socket) })),
  ])
  define_property(api, "aiBusy", fn() { @core.any(room.ai_busy) }, fn(value) {
    room.ai_busy = value.cast()
  })
  define_property(
    api,
    "aiLastRequest",
    fn() { @core.any(room.ai_last_request) },
    fn(value) { room.ai_last_request = value.cast() },
  )
  api
}

///|
pub fn create_registry(host : @core.Any) -> @core.Any {
  try {
    let configured = @core.global_this()
      ._get("process")
      ._get("env")
      ._get("POIETRA_DATA_DIR")
    let directory = resolve_path(
      if @core.is_nullish(configured) || @core.equal(configured, @core.any("")) {
        ".data"
      } else {
        configured.cast()
      },
      "",
    )
    @fs.mkdir_sync(directory, recursive=true)
    let rooms : @collection.JsMap[String, @core.Any] = @collection.JsMap::new()
    let make = fn(id : String) {
      create_room(id, directory, host) catch {
        error => rethrow(error)
      }
    }
    @core.from_entries([
      ("rooms", rooms.to_any()),
      ("Room", constructor_adapter(make)),
      (
        "getRoom",
        @core.any(fn(id : String) {
          if !@assets.valid_room(id) {
            @core.throw_error("Invalid room")
          }
          if rooms.get(id) is Some(existing) {
            rooms.delete(id) |> ignore
            rooms.set(id, existing) |> ignore
            return existing
          }
          if rooms.size() >= 100 {
            let evicted = Ref(false)
            rooms.forEach(fn(room, key) {
              if !evicted.val && (room._call("dispose", []).cast() : Bool) {
                rooms.delete(key) |> ignore
                evicted.val = true
              }
            })
            if rooms.size() >= 100 {
              @core.throw_error("Room limit reached")
            }
          }
          let room = make(id)
          rooms.set(id, room) |> ignore
          room
        }),
      ),
    ])
  } catch {
    error => rethrow(error)
  }
}
