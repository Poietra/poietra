///|
fn active(storage : @core.Any, now : Double) -> @policy.Record? {
  let value = @auth.read_record(
    storage._get("kv")._call("get", [@core.any("record")]),
  )
  match value {
    Some(record) if record.expires() > now => Some(record)
    _ => None
  }
}

///|
fn create_record(ctx : @core.Any) -> @core.Any {
  let storage = ctx._get("storage")
  let kv = storage._get("kv")
  @core.from_entries([
    (
      "put",
      @core.any(fn(value) {
        @core.from_async(async fn() {
          guard @auth.read_record(value) is Some(record) else {
            @core.throwable(fn() { @core.throw_error("Invalid auth record") })
            return
          }
          @core.throwable(fn() {
            kv._call("put", [@core.any("record"), @auth.record_value(record)])
          })
          |> ignore
          @http.call_promise(storage, "setAlarm", [@core.any(record.expires())]).wait()
          |> ignore
        })
        |> @http.native_errors
      }),
    ),
    (
      "getSession",
      @core.any(fn(now) {
        match active(storage, now) {
          Some(Session(session)) => @auth.record_value(Session(session))
          _ => @core.null()
        }
      }),
    ),
    (
      "takeFlow",
      @core.any(fn(provider : String, browser_hash, origin, now) {
        guard active(storage, now) is Some(Flow(flow)) &&
          flow.provider.name() == provider &&
          flow.browser_hash == browser_hash &&
          flow.origin == origin else {
          return @core.null()
        }
        kv._call("delete", [@core.any("record")]) |> ignore
        @auth.record_value(Flow(flow))
      }),
    ),
    (
      "erase",
      @core.any(fn() {
        @core.from_async(async fn() {
          kv._call("delete", [@core.any("record")]) |> ignore
          @http.call_promise(storage, "deleteAlarm", []).wait() |> ignore
          @http.call_promise(storage, "deleteAll", []).wait() |> ignore
        })
        |> @http.native_errors
      }),
    ),
    (
      "alarm",
      @core.any(fn() {
        @core.from_async(async fn() {
          @http.call_promise(storage, "deleteAll", []).wait() |> ignore
        })
        |> @http.native_errors
      }),
    ),
  ])
}

///|
fn create_account(ctx : @core.Any) -> @core.Any {
  let storage : @cf.DurableObjectStorage = ctx._get("storage").cast()
  let sql = storage.sql()
  sql.exec_raw(
    "CREATE TABLE IF NOT EXISTS projects (room_id TEXT PRIMARY KEY, name TEXT NOT NULL, updated_at INTEGER NOT NULL)",
  )
  |> ignore
  sql.exec_raw(
    "CREATE TABLE IF NOT EXISTS project_dismissals (room_id TEXT PRIMARY KEY)",
  )
  |> ignore
  @core.from_entries([
    (
      "listProjects",
      @core.any(fn() {
        let values = sql
          .exec_raw(
            "SELECT room_id AS roomId,name,updated_at AS updatedAt FROM projects ORDER BY updated_at DESC,room_id",
          )
          .to_array()
        @core.any(FixedArray::makei(values.length(), fn(i) { values[i] }))
      }),
    ),
    (
      "putProject",
      @core.any(fn(value, intent : @core.Any) {
        let project = @auth.read_project(value)
        if @core.equal(intent, @core.any("visit")) &&
          !sql
          .exec1(
            "SELECT room_id FROM project_dismissals WHERE room_id=?",
            @core.any(project.room),
          )
          .to_array()
          .is_empty() {
          return false
        }
        let exists = !sql
          .exec1(
            "SELECT room_id FROM projects WHERE room_id=?",
            @core.any(project.room),
          )
          .to_array()
          .is_empty()
        let count : Double = if exists {
          0.0
        } else {
          sql
          .exec_raw("SELECT COUNT(*) AS total FROM projects")
          .one()
          ._get("total")
          .cast()
        }
        if !exists && count >= @policy.project_limit.to_double() {
          return false
        }
        ctx
        ._get("storage")
        ._call("transactionSync", [
          @core.any(fn() {
            sql.exec3(
              "INSERT INTO projects (room_id,name,updated_at) VALUES (?,?,?) ON CONFLICT(room_id) DO UPDATE SET name=excluded.name,updated_at=excluded.updated_at",
              @core.any(project.room),
              @core.any(project.name),
              @core.any(project.updated),
            )
            |> ignore
            sql.exec1(
              "DELETE FROM project_dismissals WHERE room_id=?",
              @core.any(project.room),
            )
            |> ignore
          }),
        ])
        |> ignore
        true
      }),
    ),
    (
      "deleteProject",
      @core.any(fn(room : String) {
        ctx
        ._get("storage")
        ._call("transactionSync", [
          @core.any(fn() {
            sql.exec1("DELETE FROM projects WHERE room_id=?", @core.any(room))
            |> ignore
            sql.exec1(
              "INSERT OR IGNORE INTO project_dismissals (room_id) VALUES (?)",
              @core.any(room),
            )
            |> ignore
          }),
        ])
        |> ignore
      }),
    ),
  ])
}

///|
extern "js" fn class_adapter(create : (@core.Any) -> @core.Any) -> @core.Any =
  #|create => function Controller(ctx, _env) { return create(ctx); }

///|
pub fn record_class() -> @core.Any {
  class_adapter(create_record)
}

///|
pub fn account_class() -> @core.Any {
  class_adapter(create_account)
}

///|
pub fn repository(env : @core.Any) -> @core.Any {
  let record = fn(key : String) {
    env._get("AUTH_RECORDS")._call("getByName", [@core.any(key)])
  }
  let account = fn(user : String) {
    env._get("USER_ACCOUNTS")._call("getByName", [@core.any(user)])
  }
  @core.from_entries([
    (
      "putRecord",
      @core.any(fn(key, value : @core.Any) { record(key)._call("put", [value]) }),
    ),
    (
      "getSession",
      @core.any(fn(key, now : Double) {
        record(key)._call("getSession", [@core.any(now)])
      }),
    ),
    (
      "takeFlow",
      @core.any(fn(
        key,
        provider : String,
        browser_hash : String,
        origin : String,
        now : Double,
      ) {
        record(key)._call("takeFlow", [
          @core.any(provider),
          @core.any(browser_hash),
          @core.any(origin),
          @core.any(now),
        ])
      }),
    ),
    ("deleteRecord", @core.any(fn(key) { record(key)._call("erase", []) })),
    (
      "listProjects",
      @core.any(fn(user) { account(user)._call("listProjects", []) }),
    ),
    (
      "putProject",
      @core.any(fn(user, value : @core.Any, intent : @core.Any) {
        account(user)._call("putProject", [value, intent])
      }),
    ),
    (
      "deleteProject",
      @core.any(fn(user, room : String) {
        account(user)._call("deleteProject", [@core.any(room)])
      }),
    ),
  ])
}

///|
pub fn worker_auth(env : @core.Any) -> @core.Any {
  @auth.create_service(
    env,
    repository(env),
    @core.undefined(),
    @core.undefined(),
  )
}
