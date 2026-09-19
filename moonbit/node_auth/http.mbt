///|
#module("#poietra/node-host")
extern "js" fn web_body(request : @core.Any) -> @core.Any = "webRequestBody"

///|
fn native_array(value : @core.Any) -> Bool {
  @core.global_this()._get("Array")._call("isArray", [value]).cast()
}

///|
async fn handle(
  service : @core.Any,
  request : @core.Any,
  response : @core.Any,
) -> Bool {
  let location = @http.optional_string(request._get("url")).unwrap_or("/")
  let pathname = location.split("?").to_array()[0].to_owned()
  if !@policy.is_auth_path(pathname) {
    return false
  }
  try {
    let global = @core.global_this()
    let headers = @core.new(global._get("Headers"), [])
    let input = request._get("headers")
    for name in @core.object_keys(input) {
      let value = input._get(name)
      if native_array(value) {
        let values : FixedArray[String] = value.cast()
        for value in values {
          headers._call("append", [@core.any(name), @core.any(value)]) |> ignore
        }
      } else if !@core.is_nullish(value) {
        headers._call("set", [@core.any(name), value]) |> ignore
      }
    }
    let host = @http.optional_string(input._get("host")).unwrap_or("localhost")
    let url = @core.throwable(fn() {
      @core.new(global._get("URL"), [
        @core.any(location),
        @core.any("http://" + host),
      ])
    })
    let method_ : String = request._get("method").cast()
    let init = @core.from_entries([
      ("method", @core.any(method_)),
      ("headers", headers),
    ])
    if method_ != "GET" && method_ != "HEAD" {
      init._set("body", web_body(request))
      init._set("duplex", @core.any("half"))
    }
    let wrapped = @core.throwable(fn() {
      @core.new(global._get("Request"), [url, init])
    })
    let result = @http.call_promise(service, "handle", [wrapped]).wait()
    if @core.is_nullish(result) {
      return false
    }
    response._set("statusCode", result._get("status"))
    let output = result._get("headers")
    output._call("forEach", [
      @core.any(fn(value : String, name : String) {
        if name != "set-cookie" {
          response._call("setHeader", [@core.any(name), @core.any(value)])
          |> ignore
        }
      }),
    ])
    |> ignore
    let cookies : FixedArray[String] = output._call("getSetCookie", []).cast()
    if cookies.length() > 0 {
      response._call("setHeader", [@core.any("Set-Cookie"), @core.any(cookies)])
      |> ignore
    }
    let text = @http.call_promise(result, "text", []).wait()
    response._call("end", [text]) |> ignore
  } catch {
    _ => {
      response._call("writeHead", [
        @core.any(503),
        @http.headers_object([
          ("Content-Type", "application/json"),
          ("Cache-Control", "no-store"),
        ]),
      ])
      |> ignore
      response._call("end", [
        @core.any(
          "{\"error\":\"アカウント情報を取得できませんでした。\"}",
        ),
      ])
      |> ignore
    }
  }
  true
}

///|
pub fn create_node_auth(config : @core.Any, directory : String) -> @core.Any {
  try {
    let repository = create_repository(directory)
    repository._call("cleanup", []) |> ignore
    let global = @core.global_this()
    let timer = global._call("setInterval", [
      @core.any(fn() { repository._call("cleanup", []) |> ignore }),
      @core.any(60000),
    ])
    timer._call("unref", []) |> ignore
    let service = @auth.create_service(
      config,
      repository,
      @core.undefined(),
      @core.undefined(),
    )
    let callback = @core.any(fn(request, response) {
      @core.from_async(async fn() { handle(service, request, response) })
      |> @http.native_errors
    })
    callback._set(
      "dispose",
      @core.any(fn() { global._call("clearInterval", [timer]) |> ignore }),
    )
    callback
  } catch {
    error => {
      @core.throw_(@http.native_error(error))
      @core.undefined()
    }
  }
}
