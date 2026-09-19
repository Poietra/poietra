///|
priv struct AuthService {
  config : @core.Any
  repository : @core.Any
  transport : (@core.Any, @core.Any) -> @core.Promise[@web.Response]
  now : () -> Double
}

///|
fn fail(message : String) -> Unit raise {
  @core.throwable(fn() { @core.throw_error(message) })
}

///|
fn url(value : String, base? : String) -> @core.Any raise {
  @core.throwable(fn() {
    @core.new(@core.global_this()._get("URL"), [
      @core.any(value),
      match base {
        Some(base) => @core.any(base)
        None => @core.undefined()
      },
    ])
  })
}

///|
fn get_string(value : @core.Any, field : String) -> String {
  value._get(field).cast()
}

///|
fn secure(url : @core.Any) -> Bool {
  @core.equal(url._get("protocol"), @core.any("https:"))
}

///|
fn query(url : @core.Any, name : String) -> String? {
  @http.optional_string(
    url._get("searchParams")._call("get", [@core.any(name)]),
  )
}

///|
fn read_cookie(
  request : @web.Request,
  url : @core.Any,
  kind : String,
) -> String? {
  @policy.read_cookie(
    @http.header(request.as_any()._get("headers"), "Cookie").unwrap_or(""),
    @policy.cookie_name(secure(url), kind),
  )
}

///|
fn credentials(
  config : @core.Any,
  provider : @policy.Provider,
) -> (String, String) {
  let prefix = match provider {
    Google => "GOOGLE"
    GitHub => "GITHUB"
  }
  let read = fn(field) {
    @editor.trim_text(
      @http.optional_string(config._get(prefix + field)).unwrap_or(""),
    ).to_owned()
  }
  (read("_CLIENT_ID"), read("_CLIENT_SECRET"))
}

///|
fn AuthService::enabled(
  self : AuthService,
  url : @core.Any,
  provider : @policy.Provider,
) -> Bool {
  let loopback = @core.equal(url._get("protocol"), @core.any("http:")) &&
    ["localhost", "127.0.0.1", "[::1]"].contains(get_string(url, "hostname"))
  let configured = @http.optional_string(self.config._get("AUTH_ORIGIN"))
  let (id, secret) = credentials(self.config, provider)
  (secure(url) || loopback) &&
  (
    configured is None ||
    configured == Some("") ||
    configured == Some(get_string(url, "origin"))
  ) &&
  !id.is_empty() &&
  !secret.is_empty()
}

///|
fn response(
  value : @core.Any,
  status? : Int = 200,
  cookies? : Array[String] = [],
) -> @core.Any {
  let headers = @core.new(@core.global_this()._get("Headers"), [
    @http.headers_object([
      ("Cache-Control", "no-store"),
      ("Referrer-Policy", "no-referrer"),
      ("X-Content-Type-Options", "nosniff"),
    ]),
  ])
  for value in cookies {
    headers._call("append", [@core.any("Set-Cookie"), @core.any(value)])
    |> ignore
  }
  if status == 204 {
    @web.Response::new_with_body(body=@core.null(), status~, headers~).as_any()
  } else {
    @web.Response::json_(
      value,
      options=@core.from_entries([
        ("status", @core.any(status)),
        ("headers", headers),
      ]),
    ).as_any()
  }
}

///|
fn error_response(message : String, status : Int) -> @core.Any {
  response(@core.from_entries([("error", @core.any(message))]), status~)
}

///|
fn redirect(target : String, cookies : Array[String]) -> @core.Any {
  let headers = @core.new(@core.global_this()._get("Headers"), [
    @http.headers_object([
      ("Location", target),
      ("Cache-Control", "no-store"),
      ("Referrer-Policy", "no-referrer"),
    ]),
  ])
  for value in cookies {
    headers._call("append", [@core.any("Set-Cookie"), @core.any(value)])
    |> ignore
  }
  @web.Response::new_with_body(body=@core.null(), status=303, headers~).as_any()
}

///|
pub fn safe_return_to(value : @core.Any, origin : String) -> String {
  guard @http.optional_string(value) is Some(value) &&
    @policy.safe_return_input(value) else {
    return "/"
  }
  try {
    let decoded : String = @core.throwable(fn() {
      @core.global_this()._call("decodeURIComponent", [@core.any(value)]).cast()
    })
    if !@policy.safe_decoded_return(decoded) {
      return "/"
    }
    let target = url(value, base=origin)
    let path = get_string(target, "pathname")
    if get_string(target, "origin") != origin ||
      path.has_prefix("//") ||
      path.has_prefix("/api/") ||
      path.has_prefix("/sync/") {
      return "/"
    }
    path + get_string(target, "search") + get_string(target, "hash")
  } catch {
    _ => "/"
  }
}

///|
fn base64_url(bytes : @buffer.Uint8Array) -> String {
  let input = Bytes::makei(bytes.length(), fn(i) { bytes.get_at(i).to_byte() })
  let encoded = @base64.encode(input[:], padding=false)
  let result = StringBuilder()
  for c in encoded.iter() {
    result.write_char(
      match c {
        '+' => '-'
        '/' => '_'
        _ => c
      },
    )
  }
  result.to_string()
}

///|
fn random_token() -> String {
  base64_url(
    @crypto.Crypto::get().getRandomValues(@buffer.Uint8Array::from_size(32)),
  )
}

///|
pub fn auth_hash(value : String) -> @core.Promise[String] {
  @core.from_async(async fn() {
    let encoder = @core.new(@core.global_this()._get("TextEncoder"), [])
    let digest = @crypto.Crypto::get().subtle.digest(
      "SHA-256",
      encoder._call("encode", [@core.any(value)]),
    )
    base64_url(@buffer.Uint8Array::from_array_buffer(digest))
  })
  |> @http.native_errors
}

///|
async fn record_key(kind : String, token : String) -> String {
  kind + ":" + auth_hash(token).wait()
}

///|
async fn bounded_json(message : @core.Any, maximum : Int) -> @core.Any {
  let body = message._get("body")
  if @core.is_nullish(body) {
    fail("Missing body")
  }
  let stream : @streams.ReadableStream = body.cast()
  let reader = @core.throwable(fn() { stream.get_reader() })
  defer reader.release_lock()
  let bytes = @buffer.Uint8Array::from_size(maximum)
  let mut size = 0
  while true {
    let step = reader.read()
    if (step._get("done").cast() : Bool) {
      break
    }
    let chunk : @buffer.Uint8Array = step._get("value").cast()
    let length : Double = chunk.as_any()._get("byteLength").cast()
    if length > (maximum - size).to_double() {
      reader.cancel()
      fail("Body too large")
    }
    @core.throwable(fn() {
      bytes.as_any()._call("set", [chunk.as_any(), @core.any(size)])
    })
    |> ignore
    size += length.to_int()
  }
  let decoder = @core.new(@core.global_this()._get("TextDecoder"), [])
  let text = decoder._call("decode", [
    bytes.as_any()._call("subarray", [@core.any(0), @core.any(size)]),
  ])
  @core.throwable(fn() {
    @core.global_this()._get("JSON")._call("parse", [text])
  })
}

///|
async fn AuthService::session(
  self : AuthService,
  request : @web.Request,
  url : @core.Any,
) -> @policy.Session? {
  guard read_cookie(request, url, "session") is Some(token) else { return None }
  let value = @http.call_promise(self.repository, "getSession", [
    @core.any(record_key("session", token)),
    @core.any((self.now)()),
  ]).wait()
  match read_record(value) {
    Some(Session(session)) => Some(session)
    _ => None
  }
}
