///|
pub fn start_server(runtime : @core.Any) -> @core.Promise[@core.Any] {
  @core.from_async(async fn() {
    let process = @core.global_this()._get("process")
    let env = process._get("env")
    let production = string(env, "NODE_ENV") == "production"
    let port : Double = @core.global_this()
      ._call("Number", [@core.any(string(env, "PORT", fallback="5173"))])
      .cast()
    let registry = runtime._get("registry")
    let server = runtime._call("createServer", [])
    let sockets = @core.new(runtime._get("WebSocketServer"), [
      @core.from_entries([
        ("noServer", @core.any(true)),
        ("maxPayload", @core.any(2097152)),
      ]),
    ])
    server._call("on", [
      @core.any("upgrade"),
      @core.any(fn(request : @core.Any, socket : @core.Any, head : @core.Any) {
        try {
          let path = string(location(request), "pathname")
          if !path.has_prefix("/sync/") {
            return
          }
          let id = path[6:].to_owned()
          if !@assets.valid_room(id) {
            socket._call("destroy", []) |> ignore
            return
          }
          @core.throwable(fn() {
            let room = registry._call("getRoom", [@core.any(id)])
            sockets._call("handleUpgrade", [
              request,
              socket,
              head,
              @core.any(fn(ws : @core.Any) {
                room._call("connect", [ws]) |> ignore
              }),
            ])
          })
          |> ignore
        } catch {
          _ => socket._call("destroy", []) |> ignore
        }
      }),
    ])
    |> ignore
    let vite = if production {
      @core.null()
    } else {
      @http.call_promise(runtime, "loadVite", [
        @core.from_entries([
          (
            "server",
            @core.from_entries([
              ("middlewareMode", @core.any(true)),
              ("hmr", @core.from_entries([("server", server)])),
            ]),
          ),
          ("appType", @core.any("spa")),
        ]),
      ]).wait()
    }
    let service : Server = {
      env,
      runtime,
      registry,
      vite,
      production,
      static_root: resolve_path("dist", ""),
      auth: @auth.create_node_auth(
        env,
        resolve_path(
          string(env, "POIETRA_DATA_DIR", fallback=".data"),
          "accounts",
        ),
      ),
    }
    server._call("on", [
      @core.any("request"),
      @core.any(fn(request, response) {
        @core.from_async(async fn() {
          service.handle(request, response) catch {
            error =>
              if (response._get("headersSent").cast() : Bool) {
                response._call("destroy", [@http.native_error(error)]) |> ignore
              } else {
                error_response(
                  response, 503, "リクエストを処理できませんでした。もう一度お試しください。",
                )
              }
          }
        })
        |> @http.native_errors
      }),
    ])
    |> ignore
    server._call("listen", [
      @core.any(port),
      @core.any("0.0.0.0"),
      @core.any(fn() {
        @core.global_this()
        ._get("console")
        ._call("log", [
          @core.any(
            "Poietra is ready at http://localhost:\{port} (" +
            (if production { "production" } else { "development" }) +
            ")",
          ),
        ])
        |> ignore
      }),
    ])
    |> ignore
    for signal in ["SIGINT", "SIGTERM"] {
      process._call("on", [
        @core.any(signal),
        @core.any(fn() {
          registry
          ._get("rooms")
          ._call("forEach", [
            @core.any(fn(room : @core.Any) {
              room._call("persist", []) |> ignore
            }),
          ])
          |> ignore
          server._call("close", []) |> ignore
          process._call("exit", [@core.any(0)]) |> ignore
        }),
      ])
      |> ignore
    }
    server
  })
  |> @http.native_errors
}
