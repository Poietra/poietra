///|
fn response(body : @core.Any, status : Int, mime : String) -> @core.Any {
  @core.new(@core.global_this()._get("Response"), [
    body,
    @core.from_entries([
      ("status", @core.any(status)),
      (
        "headers",
        @core.from_entries([
          ("Content-Type", @core.any(mime)),
          ("Cache-Control", @core.any("no-store")),
          ("X-Content-Type-Options", @core.any("nosniff")),
        ]),
      ),
    ]),
  ])
}

///|
fn json_response(value : @core.Any, status : Int) -> @core.Any {
  response(
    @core.any(@core.json_stringify(value)),
    status,
    "application/json; charset=utf-8",
  )
}

///|
fn error_response(message : String, status : Int) -> @core.Any {
  json_response(@core.from_entries([("error", @core.any(message))]), status)
}

///|
pub fn create_http_handler(host : @core.Any) -> @core.Any {
  let busy = Ref(false)
  @core.any(fn(request : @core.Any) -> @core.Promise[@core.Any] {
    @core.from_async(async fn() {
      let method_ : String = request._get("method").cast()
      let url = @core.new(@core.global_this()._get("URL"), [request._get("url")])
      let path : String = url._get("pathname").cast()
      if (method_ == "GET" || method_ == "HEAD") &&
        [
          "/openapi.json", "/schemas/project.json", "/examples/hello.poietra.json",
        ].contains(path) {
        let document = match path {
          "/openapi.json" => @api.openapi_json(url._get("origin").cast())
          "/schemas/project.json" => @api.project_schema_json()
          _ => @api.example_json()
        }
        let output = response(
          if method_ == "HEAD" {
            @core.null()
          } else {
            @core.any(document)
          },
          200,
          "application/json; charset=utf-8",
        )
        for
          (name, value) in [
            ("Access-Control-Allow-Origin", "*"),
            ("Cache-Control", "public, max-age=300"),
            (
              "Link", "</openapi.json>; rel=\"service-desc\"; type=\"application/json\", <https://poietra.com/developers/>; rel=\"service-doc\"; type=\"text/html\"",
            ),
          ] {
          output
          ._get("headers")
          ._call("set", [@core.any(name), @core.any(value)])
          |> ignore
        }
        return output
      }
      let authorized : Bool = host._call("authorized", [request]).cast()
      if !authorized {
        return error_response("Unauthorized request.", 401)
      }
      let same_origin : Bool = host._call("sameOrigin", [request]).cast()
      if !same_origin {
        return error_response("Cross-origin requests are not accepted.", 403)
      }
      if path == "/capabilities" && method_ == "GET" {
        return json_response(@headless.capabilities(), 200)
      }
      if path != "/render" && path != "/inspect" {
        return error_response("Not found.", 404)
      }
      if method_ != "POST" {
        return error_response(
          "Use POST with a portable Poietra JSON file.", 405,
        )
      }
      let content_type = request
        ._get("headers")
        ._call("get", [@core.any("content-type")])
      if @core.is_nullish(content_type) ||
        !((content_type.cast() : String) == "application/json" ||
        (content_type.cast() : String).has_prefix("application/json;")) {
        return error_response("Content-Type must be application/json.", 415)
      }
      if busy.val {
        return error_response(
          "A render is already running. Retry after it finishes.", 429,
        )
      }
      busy.val = true
      defer {
        busy.val = false
      }
      try {
        let options = @core.new_object()
        let query = url._get("searchParams")
        let keys : FixedArray[String] = query_keys(query)
        for key in keys {
          if key != "format" &&
            key != "width" &&
            key != "height" &&
            key != "fps" &&
            key != "timeMs" {
            return error_response("Unknown render option: \{key}.", 400)
          }
          let values : FixedArray[String] = query
            ._call("getAll", [@core.any(key)])
            .cast()
          if values.length() != 1 || values[0].is_empty() {
            return error_response("Supply one value for \{key}.", 400)
          }
          options._set(
            key,
            if key == "format" {
              @core.any(values[0])
            } else {
              @core.global_this()._get("Number")._invoke([@core.any(values[0])])
            },
          )
        }
        let text : String = invoke(host, "readBody", [
          request,
          @core.any(33554432),
        ]).cast()
        if path == "/inspect" {
          return json_response(
            @core.throwable(fn() { @headless.inspect_project_file(text) }),
            200,
          )
        }
        options._set("signal", request._get("signal"))
        let result = invoke(host, "render", [@core.any(text), options])
        let output = response(
          result._get("bytes"),
          200,
          result._get("mimeType").cast(),
        )
        output
        ._get("headers")
        ._call("set", [
          @core.any("Content-Disposition"),
          @core.any(
            "attachment; filename=\"poietra.\{result._get("format").to_string()}\"",
          ),
        ])
        |> ignore
        for
          (header, field) in [
            ("X-Poietra-Frames", "frames"),
            ("X-Poietra-Rasterized-Frames", "rasterizedFrames"),
            ("X-Poietra-Duration-Ms", "durationMs"),
          ] {
          output
          ._get("headers")
          ._call("set", [@core.any(header), result._get(field)])
          |> ignore
        }
        output
      } catch {
        error => {
          let value = @headless.native_error(error)
          let status = if @core.equal(
              value._get("name"),
              @core.any("TimeoutError"),
            ) {
            504
          } else if @core.equal(value._get("status"), @core.any(413)) {
            413
          } else {
            422
          }
          error_response(value._get("message").to_string(), status)
        }
      }
    }).catch_(fn(error) {
      @core.Promise::reject(@headless.native_error(error)).to_any().cast()
    })
  })
}

///|
extern "js" fn query_keys(value : @core.Any) -> FixedArray[String] =
  #|value => [...value.keys()]

///|
async fn invoke(
  host : @core.Any,
  name : String,
  args : FixedArray[@core.Any],
) -> @core.Any {
  @core.Promise::resolve(@core.throwable(fn() { host._call(name, args) })).wait()
}
