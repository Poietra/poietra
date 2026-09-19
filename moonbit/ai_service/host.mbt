///|
priv suberror AiFailure {
  AiFailure(@core.Any)
}

///|
fn native_error(error : Error) -> @core.Any {
  match error {
    AiFailure(value) => value
    _ => @http.native_error(error)
  }
}

///|
fn[T] native_errors(promise : @core.Promise[T]) -> @core.Promise[T] {
  promise.catch_(fn(error) {
    @core.Promise::reject(native_error(error)).to_any().cast()
  })
}

///|
fn fail(message : String) -> Unit raise {
  raise AiFailure(
    @core.new(@core.global_this()._get("Error"), [@core.any(message)]),
  )
}

///|
extern "js" fn instance_of(value : @core.Any, type_ : @core.Any) -> Bool =
  #|(value, type) => value instanceof type

///|
extern "js" fn owns(value : @core.Any, key : String) -> Bool =
  #|(value, key) => Object.hasOwn(value, key)

///|
fn now() -> Double {
  @core.global_this()._get("Date")._call("now", []).cast()
}

///|
fn json(value : @core.Any) -> String {
  @core.global_this()._get("JSON")._call("stringify", [value]).cast()
}

///|
fn log(
  level : String,
  event : String,
  fields : Array[(String, @core.Any)],
) -> Unit {
  let value = @core.from_entries(fields)
  value._set("event", @core.any(event))
  @core.global_this()._get("console")._call(level, [@core.any(json(value))])
  |> ignore
}

///|
fn open_scope() -> RequestScope {
  let controller = @core.new(@core.global_this()._get("AbortController"), [])
  let timeout_error = @core.new(@core.global_this()._get("Error"), [
    @core.any(
      "AI の処理が時間内に完了しませんでした。依頼を小さく分けてお試しください。",
    ),
  ])
  let pending : @core.PromiseResolvers[@core.Any] = @core.Promise::withResolvers()
  let timer = @core.global_this()._call("setTimeout", [
    @core.any(fn() {
      controller._call("abort", []) |> ignore
      pending.reject(AiFailure(timeout_error))
    }),
    @core.any(170000),
  ])
  {
    started: now(),
    controller,
    timeout_error,
    deadline: pending.promise,
    timer,
  }
}

///|
fn RequestScope::elapsed(self : RequestScope) -> Double {
  now() - self.started
}

///|
fn RequestScope::check(self : RequestScope) -> Unit raise {
  if (self.controller._get("signal")._get("aborted").cast() : Bool) {
    raise AiFailure(self.timeout_error)
  }
}

///|
fn RequestScope::close(self : RequestScope) -> Unit {
  @core.global_this()._call("clearTimeout", [self.timer]) |> ignore
}

///|
async fn RequestScope::wait(
  self : RequestScope,
  promise : @core.Promise[@core.Any],
) -> @core.Any {
  let result = @core.Promise::race([promise, self.deadline]).wait()
  self.check()
  result
}

///|
fn rejection_reason(error : Error, runtime : @core.Any) -> String {
  let value = native_error(error)
  if instance_of(value, runtime._get("ZodError")) {
    array(value._get("issues"))
    .map(fn(issue) {
      let path : String = issue
        ._get("path")
        ._call("join", [@core.any(".")])
        .cast()
      (if path.is_empty() { "proposal" } else { path }) +
      ": " +
      string(issue, "message")
    })
    .join("; ")
  } else if instance_of(value, @core.global_this()._get("Error")) {
    string(value, "message")
  } else {
    @core.global_this()._call("String", [value]).cast()
  }
}

///|
pub fn ai_error_message(error : @core.Any, runtime : @core.Any) -> String {
  if instance_of(error, runtime._get("ZodError")) {
    return "編集内容を検証できませんでした。依頼を具体的にしてお試しください。"
  }
  if instance_of(error, runtime._get("OpenAI")._get("APIError")) {
    log("error", "ai_request_failed", [
      ("status", error._get("status")),
      ("code", error._get("code")),
    ])
    return "AI への接続に失敗しました。しばらくしてからお試しください。"
  }
  if instance_of(error, @core.global_this()._get("Error")) {
    string(error, "message")
  } else {
    "編集案の作成に失敗しました。"
  }
}
