///|
pub fn load_kernel() -> @core.Promise[@core.Any] {
  @core.from_async(async fn() {
    let global = @core.global_this()
    let response = @http.call_promise(global, "fetch", [
      @core.any("/wasm/poietra_core.wasm"),
    ]).wait()
    if !(response._get("ok").cast() : Bool) {
      @core.throwable(fn() {
        @core.throw_error(
          "動きのエンジンを読み込めませんでした。ページを再読み込みしてください。",
        )
      })
    }
    let bytes = @http.call_promise(response, "arrayBuffer", []).wait()
    let result = @http.call_promise(global._get("WebAssembly"), "instantiate", [
      bytes,
    ]).wait()
    result._get("instance")._get("exports")
  })
  |> @http.native_errors
}
