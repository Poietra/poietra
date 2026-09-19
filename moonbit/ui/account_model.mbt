///|
priv struct AccountView {
  session : @editor.AccountSession?
  projects : Array[@editor.AccountProject]
  loading : Bool
  list_loading : Bool
  pending : String
  error : String
  excluded : @editor.AccountRoom?
}

///|
priv struct AccountWrite {
  controller : @core.Any
  identity : String
  operation : @editor.AccountOperation
}

///|
priv struct AccountController {
  mut view : AccountView
  mut identity : String?
  mut mounted : Bool
  mut session_request : @core.Any
  mut list_request : @core.Any
  mut write : AccountWrite?
  mut saved : @editor.AccountSave?
  mut attempted : @editor.AccountSave?
  publish : (AccountView) -> Unit
}

///|
fn AccountController::update(
  self : AccountController,
  view : AccountView,
) -> Unit {
  self.view = view
  if self.mounted {
    (self.publish)(view)
  }
}

///|
fn account_cancel(request : @core.Any) -> Unit {
  if !@core.is_nullish(request) {
    request._call("abort", []) |> ignore
  }
}

///|
fn account_session(value : @core.Any) -> @editor.AccountSession {
  let user = value._get("user")
  let providers = value._get("providers")
  {
    user: if truthy(user) {
      Some({
        id: user._get("id").cast(),
        name: user._get("name").cast(),
        provider: if @core.equal(user._get("provider"), @core.any("google")) {
          @editor.Google
        } else {
          @editor.GitHub
        },
      })
    } else {
      None
    },
    google: truthy(providers._get("google")),
    github: truthy(providers._get("github")),
  }
}

///|
fn account_project(value : @core.Any) -> @editor.AccountProject {
  {
    room_id: value._get("roomId").cast(),
    name: value._get("name").cast(),
    updated_at: value._get("updatedAt").cast(),
  }
}

///|
async fn account_request(path : String, init : @core.Any) -> @core.Any {
  let options = ui_shallow_copy(init)
  let signals = @core.global_this()._get("AbortSignal")
  let timeout = signals._call("timeout", [@core.any(15000)])
  let signal = init._get("signal")
  options._set(
    "signal",
    if truthy(signal) {
      signals._call("any", [
        @core.any(([signal, timeout] : FixedArray[@core.Any])),
      ])
    } else {
      timeout
    },
  )
  options._set("credentials", @core.any("same-origin"))
  options._set("cache", @core.any("no-store"))
  let response = ui_call(@core.global_this(), "fetch", [
    @core.any(path),
    options,
  ])
  let status : Int = response._get("status").cast()
  if !truthy(response._get("ok")) {
    let body = ui_call(response, "json", []) catch { _ => @core.null() }
    let message = if truthy(body) {
      optional_string(body._get("error")).unwrap_or(
        "アカウントに接続できませんでした。もう一度お試しください。",
      )
    } else {
      "アカウントに接続できませんでした。もう一度お試しください。"
    }
    let error = @core.new(@core.global_this()._get("Error"), [
      @core.any(message),
    ])
    error._set("status", @core.any(status))
    @core.throwable(fn() { @core.throw_(error) })
  }
  if status == 204 {
    @core.undefined()
  } else {
    ui_call(response, "json", [])
  }
}

///|
fn account_failure(error : Error) -> Bool {
  let native = ui_native_error(error)
  !@core.is_nullish(native) &&
  (
    @core.equal(native._get("status"), @core.any(401)) ||
    @core.equal(native._get("status"), @core.any(409))
  )
}

///|
fn account_query(fields : Map[String, @core.Any]) -> String {
  @core.new(@core.global_this()._get("URLSearchParams"), [host_record(fields)])
  ._call("toString", [])
  .cast()
}

///|
pub fn login_url(provider : String, room : String) -> String {
  let return_to = "/?" +
    account_query({ "room": @core.any(room), "projects": @core.any("1") })
  "/api/auth/login/" +
  provider +
  "?" +
  account_query({ "returnTo": @core.any(return_to) })
}
