///|
priv struct Metadata {
  mime : String
  size : Double
  key : String?
}

///|
priv struct RoomAssets {
  storage : @cf.DurableObjectStorage
  sql : @cf.SqlStorage
  bucket : @cf.R2Bucket
}

///|
priv struct Failure {
  message : String
  status : Int
}

///|
fn failure(message : String, status? : Int = 400) -> Result[String, Failure] {
  Err({ message, status, })
}

///|
fn encode_result(result : Result[String, Failure]) -> @core.Any {
  match result {
    Ok(value) =>
      @core.from_entries([("ok", @core.any(true)), ("value", @core.any(value))])
    Err(error) =>
      @core.from_entries([
        ("ok", @core.any(false)),
        ("error", @core.any(error.message)),
        ("status", @core.any(error.status)),
      ])
  }
}

///|
fn now() -> Double {
  @core.global_this()._get("Date")._call("now", []).cast()
}

///|
// Upstream alarms use Int. Absolute epoch milliseconds must remain JS numbers.
async fn set_alarm(storage : @cf.DurableObjectStorage) -> Unit {
  @http.call_promise(@core.any(storage), "setAlarm", [
    @core.any(now() + 60000.0),
  ]).wait()
  |> ignore
}

///|
async fn RoomAssets::schedule_cleanup(self : RoomAssets) -> Unit {
  if @core.is_null(
      @http.call_promise(@core.any(self.storage), "getAlarm", []).wait(),
    ) {
    set_alarm(self.storage)
  }
}

///|
fn RoomAssets::get(
  self : RoomAssets,
  kind : @assets.AssetKind,
  id : String,
) -> Metadata? {
  if !@assets.valid_digest(id) {
    return None
  }
  let rows = self.sql
    .exec2(
      "SELECT a.mime, a.size, o.object_key AS objectKey FROM " +
      kind.name() +
      " a LEFT JOIN asset_objects o ON o.kind = ? AND o.id = a.id WHERE a.id = ?",
      @core.any(kind.name()),
      @core.any(id),
    )
    .to_array()
  guard rows.get(0) is Some(row) else { return None }
  Some({
    mime: row._get("mime").cast(),
    size: row._get("size").cast(),
    key: @http.optional_string(row._get("objectKey")),
  })
}

///|
async fn RoomAssets::begin(
  self : RoomAssets,
  room : String,
  kind_name : String,
) -> Result[String, Failure] {
  guard @assets.asset_kind(kind_name) is Some(kind) && @assets.valid_room(room) else {
    return failure("Invalid asset upload")
  }
  let count : Double = self.sql
    .exec1(
      "SELECT COUNT(*) AS count FROM asset_uploads WHERE expires_ms > ?",
      @core.any(now()),
    )
    .one()
    ._get("count")
    .cast()
  if count >= 4.0 {
    return failure(
      "この部屋では素材を読み込み中です。完了してから再試行してください。",
      status=429,
    )
  }
  let uuid : String = @core.global_this()
    ._get("crypto")
    ._call("randomUUID", [])
    .cast()
  let key = "rooms/" + room + "/" + kind.name() + "/" + uuid
  // Reserve durably before starting any external upload.
  self.sql.exec3(
    "INSERT INTO asset_uploads (object_key, kind, expires_ms) VALUES (?, ?, ?)",
    @core.any(key),
    @core.any(kind.name()),
    @core.any(now() + 900000.0),
  )
  |> ignore
  self.schedule_cleanup()
  Ok(key)
}

///|
fn RoomAssets::finish(
  self : RoomAssets,
  key : String,
  digest : String,
  mime : String,
  size : Double,
) -> Result[String, Failure] {
  let pending = self.sql
    .exec1(
      "SELECT kind, expires_ms FROM asset_uploads WHERE object_key = ?",
      @core.any(key),
    )
    .to_array()
  guard pending.get(0) is Some(row) &&
    (row._get("expires_ms").cast() : Double) > now() else {
    return failure(
      "素材の読み込みがタイムアウトしました。再試行してください。",
      status=408,
    )
  }
  guard @assets.asset_kind(row._get("kind").cast()) is Some(kind) &&
    @assets.valid_digest(digest) &&
    !size.is_nan() &&
    size >= 1.0 &&
    size <= kind.file_limit().to_double() &&
    size.trunc() == size else {
    return failure("Invalid asset metadata")
  }
  match self.get(kind, digest) {
    Some(metadata) => {
      if metadata.size != size {
        return failure("素材のサイズを確認できませんでした。")
      }
      if metadata.key is Some(published) {
        return Ok(published)
      }
    }
    None => {
      let used : Double = self.sql
        .exec_raw("SELECT COALESCE(SUM(size), 0) AS size FROM " + kind.name())
        .one()
        ._get("size")
        .cast()
      if used + size > kind.room_limit().to_double() {
        return match kind {
          Image =>
            failure(
              "この部屋の画像が保存できる容量を超えました。新しいプロジェクトを作成してください。",
            )
          Media =>
            failure(
              "この部屋の音声・動画は合計 128 MB までです。新しいプロジェクトを作成してください。",
              status=413,
            )
        }
      }
      self.sql.exec3(
        "INSERT INTO " + kind.name() + " (id, mime, size) VALUES (?, ?, ?)",
        @core.any(digest),
        @core.any(mime),
        @core.any(size),
      )
      |> ignore
    }
  }
  self.sql.exec3(
    "INSERT INTO asset_objects (kind, id, object_key) VALUES (?, ?, ?)",
    @core.any(kind.name()),
    @core.any(digest),
    @core.any(key),
  )
  |> ignore
  self.sql.exec1(
    "DELETE FROM asset_uploads WHERE object_key = ?",
    @core.any(key),
  )
  |> ignore
  Ok(key)
}

///|
async fn RoomAssets::discard(self : RoomAssets, key : String) -> Unit {
  guard @assets.storage_key_kind(key) is Some(kind) else { return }
  if !self.sql
    .exec1(
      "SELECT object_key FROM asset_objects WHERE object_key = ?",
      @core.any(key),
    )
    .to_array()
    .is_empty() {
    self.sql.exec1(
      "DELETE FROM asset_uploads WHERE object_key = ?",
      @core.any(key),
    )
    |> ignore
    return
  }
  // Invalidate publication BEFORE awaiting deletion, including late uploads whose
  // original reservation has already been collected by an alarm.
  self.sql.exec2(
    "INSERT INTO asset_uploads (object_key, kind, expires_ms) VALUES (?, ?, 0) ON CONFLICT(object_key) DO UPDATE SET expires_ms = 0",
    @core.any(key),
    @core.any(kind.name()),
  )
  |> ignore
  try {
    @cloud.delete(self.bucket, key)
    @core.throwable(fn() {
      self.sql.exec1(
        "DELETE FROM asset_uploads WHERE object_key = ?",
        @core.any(key),
      )
      |> ignore
    })
  } catch {
    _ => {
      @core.global_this()
      ._get("console")
      ._call("warn", [@core.any("asset_cleanup_retry")])
      |> ignore
      self.schedule_cleanup()
    }
  }
}

///|
async fn RoomAssets::alarm(self : RoomAssets) -> Unit {
  // Consume the cursor before yielding to R2.
  let expired = self.sql
    .exec1(
      "SELECT object_key FROM asset_uploads WHERE expires_ms <= ? LIMIT 32",
      @core.any(now()),
    )
    .to_array()
  for row in expired {
    self.discard(row._get("object_key").cast())
  }
  if !self.sql
    .exec_raw("SELECT object_key FROM asset_uploads LIMIT 1")
    .to_array()
    .is_empty() {
    set_alarm(self.storage)
  }
}

///|
extern "js" fn transaction(
  storage : @cf.DurableObjectStorage,
  body : () -> Result[String, Failure],
) -> Result[String, Failure] =
  #|(storage, body) => storage.transactionSync(body)

///|
fn create_room_assets(ctx : @core.Any, bucket : @cf.R2Bucket) -> @core.Any {
  let storage : @cf.DurableObjectStorage = ctx._get("storage").cast()
  let service : RoomAssets = { storage, sql: storage.sql(), bucket, }
  service.sql.exec_raw(
    "CREATE TABLE IF NOT EXISTS asset_objects (kind TEXT NOT NULL, id TEXT NOT NULL, object_key TEXT NOT NULL UNIQUE, PRIMARY KEY (kind, id))",
  )
  |> ignore
  service.sql.exec_raw(
    "CREATE TABLE IF NOT EXISTS asset_uploads (object_key TEXT PRIMARY KEY, kind TEXT NOT NULL, expires_ms INTEGER NOT NULL)",
  )
  |> ignore
  @core.from_entries([
    (
      "get",
      @core.any(fn(kind : String, id : String) {
        match @assets.asset_kind(kind).bind(fn(k) { service.get(k, id) }) {
          Some(metadata) =>
            @core.from_entries([
              ("mime", @core.any(metadata.mime)),
              ("size", @core.any(metadata.size)),
              (
                "objectKey",
                match metadata.key {
                  Some(key) => @core.any(key)
                  None => @core.null()
                },
              ),
            ])
          None => @core.null()
        }
      }),
    ),
    (
      "begin",
      @core.any(fn(room, kind) {
        @core.from_async(async fn() { encode_result(service.begin(room, kind)) })
        |> @http.native_errors
      }),
    ),
    (
      "finish",
      @core.any(fn(key, digest, mime, size) {
        encode_result(
          transaction(storage, fn() { service.finish(key, digest, mime, size) }),
        )
      }),
    ),
    (
      "discard",
      @core.any(fn(key) {
        @core.from_async(async fn() { service.discard(key) })
        |> @http.native_errors
      }),
    ),
    (
      "alarm",
      @core.any(fn() {
        @core.from_async(async fn() { service.alarm() }) |> @http.native_errors
      }),
    ),
  ])
}

///|
extern "js" fn class_adapter(
  create : (@core.Any, @cf.R2Bucket) -> @core.Any,
) -> @core.Any =
  #|create => function RoomAssets(ctx, bucket) { return create(ctx, bucket); }

///|
pub fn room_assets_class() -> @core.Any {
  class_adapter(create_room_assets)
}
