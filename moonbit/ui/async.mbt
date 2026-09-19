///|
fn ui_native_error(error : Error) -> @core.Any {
  match error {
    @core.ThrowError(value) => value
    _ => @core.any(error)
  }
}

///|
fn[T] ui_native_errors(promise : @core.Promise[T]) -> @core.Promise[T] {
  promise.catch_(fn(error) {
    @core.Promise::reject(ui_native_error(error)).to_any().cast()
  })
}

///|
async fn ui_call(
  owner : @core.Any,
  operation : String,
  args : FixedArray[@core.Any],
) -> @core.Any {
  let value = @core.throwable(fn() { owner._call(operation, args) })
  @core.Promise::resolve(value).wait()
}

///|
fn ui_quiet(owner : @core.Any, operation : String) -> Unit {
  try @core.throwable(fn() { owner._call(operation, []) }) |> ignore catch {
    _ => ()
  }
}

///|
fn new_controller() -> @core.Any {
  @core.new(@core.global_this()._get("AbortController"), [])
}

///|
fn ui_aborted(signal : @core.Any) -> Bool {
  signal._get("aborted").cast()
}

///|
async fn wait_signal(value : @core.Any, signal : @core.Any) -> @core.Any {
  let completion : @core.PromiseResolvers[@core.Any] = @core.Promise::withResolvers()
  let abort = fn() { completion.reject(signal._get("reason").cast()) }
  signal._call("addEventListener", [
    @core.any("abort"),
    @core.any(abort),
    @core.from_entries([("once", @core.any(true))]),
  ])
  |> ignore
  defer signal._call("removeEventListener", [
      @core.any("abort"),
      @core.any(abort),
    ])
    |> ignore
  @core.Promise::resolve(value)
  .then(fn(value) {
    completion.resolve(value)
    @core.Promise::resolve(())
  })
  .catch_(fn(error) {
    completion.reject(ui_native_error(error).cast())
    @core.Promise::resolve(())
  })
  |> ignore
  if ui_aborted(signal) {
    abort()
  }
  completion.promise.wait()
}

///|
extern "js" fn ui_snapshot(value : @core.Any) -> @core.Any =
  #|value => structuredClone(value)

///|
extern "js" fn ui_shallow_copy(value : @core.Any) -> @core.Any =
  #|value => ({ ...value })
