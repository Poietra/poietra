///|
fn Room::fetch(self : Room, request : @core.Any) -> @core.Any {
  let url = @core.new(@core.global_this()._get("URL"), [request._get("url")])
  if @assets.asset_route(string(url, "pathname")) is Some(route) {
    return self.legacy_response(request, route)
  }
  let upgrade = @http.header(request._get("headers"), "Upgrade")
    .unwrap_or("")
    .to_lower()
  if upgrade != "websocket" {
    return error_response("WebSocket required", 426)
  }
  if self.sockets().length() >= 32 {
    return error_response("この部屋は満員です。", 429)
  }
  let pair = @core.new(@core.global_this()._get("WebSocketPair"), [])
  let client = pair._get("0")
  let server = pair._get("1")
  self.ctx._call("acceptWebSocket", [server]) |> ignore
  attach(server, @core.null())
  let message = @wire.encoder()
  @wire.write_uint(message, 0.0)
  self.runtime
  ._get("sync")
  ._call("writeSyncStep1", [@core.any(message), self.doc])
  |> ignore
  self.send(server, @wire.to_bytes(message))
  self.send(server, @presence.presence_message(self.all_presence()))
  @core.new(@core.global_this()._get("Response"), [
    @core.null(),
    @core.from_entries([("status", @core.any(101)), ("webSocket", client)]),
  ])
}

///|
fn create_room(
  ctx : @core.Any,
  env : @core.Any,
  runtime : @core.Any,
) -> @core.Any {
  let storage = ctx._get("storage")
  let sql : @cf.SqlStorage = storage._get("sql").cast()
  for
    statement in [
      "CREATE TABLE IF NOT EXISTS snapshot (id INTEGER PRIMARY KEY CHECK (id = 1), data BLOB NOT NULL)",
      "CREATE TABLE IF NOT EXISTS updates (seq INTEGER PRIMARY KEY AUTOINCREMENT, data BLOB NOT NULL)",
      "CREATE TABLE IF NOT EXISTS ai_lock (id INTEGER PRIMARY KEY CHECK (id = 1), request_id TEXT NOT NULL, until_ms INTEGER NOT NULL)",
      "CREATE TABLE IF NOT EXISTS images (id TEXT PRIMARY KEY, mime TEXT NOT NULL, size INTEGER NOT NULL)",
      "CREATE TABLE IF NOT EXISTS image_chunks (id TEXT NOT NULL, part INTEGER NOT NULL, data BLOB NOT NULL, PRIMARY KEY (id, part))",
      "CREATE TABLE IF NOT EXISTS media (id TEXT PRIMARY KEY, mime TEXT NOT NULL, size INTEGER NOT NULL)",
      "CREATE TABLE IF NOT EXISTS media_chunks (id TEXT NOT NULL, part INTEGER NOT NULL, data BLOB NOT NULL, PRIMARY KEY (id, part))",
      "DELETE FROM media_chunks WHERE id NOT IN (SELECT id FROM media)",
    ] {
    sql.exec_raw(statement) |> ignore
  }
  let yjs = runtime._get("Y")
  let doc = @core.new(yjs._get("Doc"), [])
  let room : Room = {
    ctx,
    env,
    runtime,
    doc,
    sql,
    storage,
    updates: 0,
    promoting: Set([]),
    assets: @core.new(@storage.room_assets_class(), [
      ctx,
      env._get("MEDIA_BUCKET"),
    ]),
  }
  let snapshots = sql
    .exec_raw("SELECT data FROM snapshot WHERE id = 1")
    .to_array()
  if !snapshots.is_empty() {
    yjs._call("applyUpdate", [
      doc,
      @buffer.Uint8Array::from_array_buffer(snapshots[0]._get("data").cast()).as_any(),
    ])
    |> ignore
  }
  for row in sql.exec_raw("SELECT data FROM updates ORDER BY seq").to_array() {
    yjs._call("applyUpdate", [
      doc,
      @buffer.Uint8Array::from_array_buffer(row._get("data").cast()).as_any(),
    ])
    |> ignore
    room.updates += 1
  }
  if snapshots.is_empty() {
    @boundary.initialize_document(doc, @boundary.make_demo_project(), yjs)
    room.compact()
  }
  if room.migrate() {
    room.compact()
  }
  @core.from_entries([
    (
      "fetch",
      @core.any(fn(request) {
        @core.from_async(fn() raise {
          @core.throwable(fn() { room.fetch(request) })
        })
        |> @http.native_errors
      }),
    ),
    (
      "webSocketMessage",
      @core.any(fn(socket, message) { room.message(socket, message) }),
    ),
    ("webSocketClose", @core.any(fn(socket) { room.remove_presence(socket) })),
    (
      "webSocketError",
      @core.any(fn(socket) {
        room.remove_presence(socket)
        (@core.throwable(fn() {
          socket._call("close", [@core.any(1011), @core.any("Connection error")])
        })
        |> ignore) catch {
          _ => ()
        }
      }),
    ),
    (
      "getAssetMetadata",
      @core.any(fn(kind : String, id : String) {
        room.assets._call("get", [@core.any(kind), @core.any(id)])
      }),
    ),
    (
      "beginAssetUpload",
      @core.any(fn(room_id : String, kind : String) {
        room.assets._call("begin", [@core.any(room_id), @core.any(kind)])
      }),
    ),
    (
      "finishAssetUpload",
      @core.any(fn(
        key : String,
        digest : String,
        mime : String,
        size : Double,
      ) {
        room.assets._call("finish", [
          @core.any(key),
          @core.any(digest),
          @core.any(mime),
          @core.any(size),
        ])
      }),
    ),
    (
      "discardAssetUpload",
      @core.any(fn(key : String) {
        room.assets._call("discard", [@core.any(key)])
      }),
    ),
    ("alarm", @core.any(fn() { room.assets._call("alarm", []) })),
    (
      "saveImage",
      @core.any(fn(room_id, bytes, mime) {
        @core.from_async(async fn() { room.save_image(room_id, bytes, mime) })
        |> @http.native_errors
      }),
    ),
    (
      "propose",
      @core.any(fn(input) {
        @core.from_async(async fn() { room.propose(input) })
        |> @http.native_errors
      }),
    ),
  ])
}

///|
extern "js" fn class_adapter(
  create : (@core.Any, @core.Any) -> @core.Any,
) -> @core.Any =
  #|create => function ProjectRoom(ctx, env) { return create(ctx, env); }

///|
pub fn room_class(runtime : @core.Any) -> @core.Any {
  class_adapter(fn(ctx, env) { create_room(ctx, env, runtime) })
}
