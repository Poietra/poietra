///|
#module("node:path")
extern "js" fn resolve_path(left : String, right : String) -> String = "resolve"

///|
#module("node:path")
extern "js" fn extension(path : String) -> String = "extname"

///|
#module("node:fs")
extern "js" fn read_stream(path : String) -> @core.Any = "createReadStream"

///|
#module("#poietra/node-host")
extern "js" fn web_body(request : @core.Any) -> @core.Any = "webRequestBody"

///|
fn string(value : @core.Any, key : String, fallback? : String = "") -> String {
  let value = @http.optional_string(value._get(key)).unwrap_or(fallback)
  if value.is_empty() {
    fallback
  } else {
    value
  }
}

///|
fn json(response : @core.Any, status : Int, value : @core.Any) -> Unit {
  response._call("writeHead", [
    @core.any(status),
    @http.headers_object([
      ("Content-Type", "application/json"),
      ("Cache-Control", "no-store"),
    ]),
  ])
  |> ignore
  response._call("end", [
    @core.global_this()._get("JSON")._call("stringify", [value]),
  ])
  |> ignore
}

///|
fn error_response(response : @core.Any, status : Int, message : String) -> Unit {
  json(response, status, @core.from_entries([("error", @core.any(message))]))
}

///|
fn send_file(response : @core.Any, filename : String, head : Bool) -> Unit {
  if head {
    response._call("end", []) |> ignore
  } else {
    let stream = read_stream(filename)
    stream._call("on", [
      @core.any("error"),
      @core.any(fn(error : @core.Any) {
        response._call("destroy", [error]) |> ignore
      }),
    ])
    |> ignore
    response._call("once", [
      @core.any("close"),
      @core.any(fn() { stream._call("destroy", []) |> ignore }),
    ])
    |> ignore
    stream._call("pipe", [response]) |> ignore
  }
}

///|
fn content_type(filename : String) -> String {
  match extension(filename) {
    ".html" => "text/html; charset=utf-8"
    ".js" => "text/javascript; charset=utf-8"
    ".css" => "text/css; charset=utf-8"
    ".svg" => "image/svg+xml"
    ".png" => "image/png"
    ".webp" => "image/webp"
    ".wasm" => "application/wasm"
    ".woff2" => "font/woff2"
    ".json" => "application/json"
    ".md" => "text/markdown; charset=utf-8"
    ".xml" => "application/xml; charset=utf-8"
    ".txt" => "text/plain; charset=utf-8"
    _ => "application/octet-stream"
  }
}

///|
priv struct Server {
  env : @core.Any
  runtime : @core.Any
  registry : @core.Any
  auth : @core.Any
  vite : @core.Any
  production : Bool
  static_root : String
}

///|
fn location(request : @core.Any) -> @core.Any raise {
  @core.throwable(fn() {
    @core.new(@core.global_this()._get("URL"), [
      @core.any(string(request, "url", fallback="/")),
      @core.any("http://localhost"),
    ])
  })
}
