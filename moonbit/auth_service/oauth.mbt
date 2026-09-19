///|
fn parameters(values : Array[(String, String)]) -> @core.Any {
  @core.new(@core.global_this()._get("URLSearchParams"), [
    @http.headers_object(values),
  ])
}

///|
async fn AuthService::identify(
  self : AuthService,
  provider : @policy.Provider,
  code : String,
  flow : @policy.Flow,
) -> @policy.User {
  let (id, secret) = credentials(self.config, provider)
  let body = parameters([
    ("grant_type", "authorization_code"),
    ("client_id", id),
    ("client_secret", secret),
    ("code", code),
    ("redirect_uri", flow.origin + "/api/auth/callback/" + provider.name()),
    ("code_verifier", flow.verifier),
  ])
  let options = @core.from_entries([
    ("method", @core.any("POST")),
    (
      "headers",
      @http.headers_object([
        ("Accept", "application/json"),
        ("Content-Type", "application/x-www-form-urlencoded"),
      ]),
    ),
    ("body", body),
    ("redirect", @core.any("error")),
    (
      "signal",
      @core.global_this()
      ._get("AbortSignal")
      ._call("timeout", [@core.any(10000)]),
    ),
  ])
  let exchanged = @core.throwable(fn() {
    (self.transport)(@core.any(provider.token_url()), options)
  }).wait()
  if !exchanged.ok {
    if exchanged.body() is Some(body) {
      body.cancel()
    }
    fail("Token exchange failed")
  }
  let token = bounded_json(exchanged.as_any(), 65536)
  if @core.is_nullish(token) || @core.typeof_(token) != "object" {
    fail("Invalid token")
  }
  let token_type : String = @core.global_this()
    ._call("String", [token._get("token_type")])
    .cast()
  guard string(token, "access_token") is Some(access) &&
    !access.is_empty() &&
    access.length() <= 8192 &&
    token_type.to_lower() == "bearer" else {
    fail("Invalid token")
    return { id: "", name: "", provider, }
  }
  let options = @core.from_entries([
    (
      "headers",
      @http.headers_object([
        ("Authorization", "Bearer " + access),
        ("Accept", "application/json"),
        ("User-Agent", "Poietra"),
      ]),
    ),
    ("redirect", @core.any("error")),
    (
      "signal",
      @core.global_this()
      ._get("AbortSignal")
      ._call("timeout", [@core.any(10000)]),
    ),
  ])
  let user_response = @core.throwable(fn() {
    (self.transport)(@core.any(provider.user_url()), options)
  }).wait()
  if !user_response.ok {
    if user_response.body() is Some(body) {
      body.cancel()
    }
    fail("User lookup failed")
  }
  let info = bounded_json(user_response.as_any(), 65536)
  if @core.is_nullish(info) || @core.typeof_(info) != "object" {
    fail("Missing user identity")
  }
  let subject = match provider {
    Google => string(info, "sub")
    GitHub => {
      let id = info._get("id")
      if @core.typeof_(id) == "number" {
        let number : Double = id.cast()
        if number > 0.0 &&
          number <= 9007199254740991.0 &&
          number.trunc() == number {
          Some((@core.global_this()._call("String", [id]).cast() : String))
        } else {
          None
        }
      } else {
        None
      }
    }
  }
  guard subject is Some(subject) &&
    !subject.is_empty() &&
    subject.length() <= 255 else {
    fail("Missing user identity")
    return { id: "", name: "", provider, }
  }
  let raw_name = string(info, "name").unwrap_or(
    string(info, "login").unwrap_or(
      match provider {
        Google => "Google user"
        GitHub => "GitHub user"
      },
    ),
  )
  {
    id: auth_hash(provider.name() + ":" + subject).wait(),
    name: @policy.user_name(raw_name, provider),
    provider,
  }
}

///|
async fn AuthService::login(
  self : AuthService,
  target : @core.Any,
  provider : @policy.Provider,
) -> @core.Any {
  if !self.enabled(target, provider) {
    return error_response(
      "このログイン方法はまだ設定されていません。", 503,
    )
  }
  let state = random_token()
  let browser = random_token()
  let verifier = random_token()
  let origin = get_string(target, "origin")
  let flow : @policy.Flow = {
    provider,
    browser_hash: auth_hash(browser).wait(),
    verifier,
    origin,
    return_to: safe_return_to(
      target._get("searchParams")._call("get", [@core.any("returnTo")]),
      origin,
    ),
    expires: (self.now)() + @policy.flow_ttl,
  }
  @http.call_promise(self.repository, "putRecord", [
    @core.any(record_key("flow", state)),
    record_value(Flow(flow)),
  ]).wait()
  |> ignore
  let authorize = url(provider.authorize())
  let (id, _) = credentials(self.config, provider)
  let params = parameters([
    ("client_id", id),
    ("redirect_uri", origin + "/api/auth/callback/" + provider.name()),
    ("response_type", "code"),
    ("scope", provider.scope()),
    ("state", state),
    ("code_challenge", auth_hash(verifier).wait()),
    ("code_challenge_method", "S256"),
  ])
  authorize._set("search", params._call("toString", []))
  redirect(get_string(authorize, "href"), [
    @policy.cookie(secure(target), "flow", browser, 600),
  ])
}

///|
async fn AuthService::callback(
  self : AuthService,
  request : @web.Request,
  target : @core.Any,
  provider : @policy.Provider,
) -> @core.Any {
  let origin = get_string(target, "origin")
  let clear = @policy.cookie(secure(target), "flow", "", 0)
  let flow = if self.enabled(target, provider) &&
    query(target, "state") is Some(state) &&
    @policy.valid_token(state) &&
    read_cookie(request, target, "flow") is Some(browser) {
    let record = @http.call_promise(self.repository, "takeFlow", [
      @core.any(record_key("flow", state)),
      @core.any(provider.name()),
      @core.any(auth_hash(browser).wait()),
      @core.any(origin),
      @core.any((self.now)()),
    ]).wait()
    match read_record(record) {
      Some(Flow(flow)) => Some(flow)
      _ => None
    }
  } else {
    None
  }
  let failure = fn(reason : String) raise {
    let target = url(
      match flow {
        Some(flow) => flow.return_to
        None => "/"
      },
      base=origin,
    )
    target
    ._get("searchParams")
    ._call("set", [@core.any("auth_error"), @core.any(reason)])
    |> ignore
    redirect(
      get_string(target, "pathname") +
      get_string(target, "search") +
      get_string(target, "hash"),
      [clear],
    )
  }
  guard flow is Some(flow) else { return failure("expired") }
  if query(target, "error") is Some(_) {
    return failure("denied")
  }
  guard query(target, "code") is Some(code) &&
    !code.is_empty() &&
    code.length() <= 4096 else {
    return failure("failed")
  }
  try {
    let user = self.identify(provider, code, flow)
    let token = random_token()
    let record : @policy.Record = Session({
      user,
      expires: (self.now)() + @policy.session_ttl,
    })
    @http.call_promise(self.repository, "putRecord", [
      @core.any(record_key("session", token)),
      record_value(record),
    ]).wait()
    |> ignore
    if read_cookie(request, target, "session") is Some(old) {
      @http.call_promise(self.repository, "deleteRecord", [
        @core.any(record_key("session", old)),
      ]).wait()
      |> ignore
    }
    redirect(flow.return_to, [
      clear,
      @policy.cookie(secure(target), "session", token, 604800),
    ])
  } catch {
    _ => failure("failed")
  }
}
