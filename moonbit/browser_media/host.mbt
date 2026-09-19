///|
priv suberror MediaFailure {
  MediaFailure(String)
}

///|
fn native_error(error : Error) -> @core.Any {
  match error {
    MediaFailure(message) =>
      @core.new(@core.global_this()._get("Error"), [@core.any(message)])
    @core.ThrowError(value) => value
    _ => @core.any(error)
  }
}

///|
fn[T] native_errors(promise : @core.Promise[T]) -> @core.Promise[T] {
  promise.catch_(fn(error) {
    @core.Promise::reject(native_error(error)).to_any().cast()
  })
}

///|
fn check_abort(signal : @core.Any) -> Unit raise {
  if !@core.is_nullish(signal) {
    @core.throwable(fn() { signal._call("throwIfAborted", []) }) |> ignore
  }
}

///|
fn join_signal(lifetime : @core.Any, request : @core.Any) -> @core.Any {
  if @core.is_nullish(request) {
    lifetime
  } else {
    @core.global_this()
    ._get("AbortSignal")
    ._call("any", [@core.any(([lifetime, request] : FixedArray[@core.Any]))])
  }
}

///|
#module("#poietra/media-host")
extern "js" fn media_runtime() -> @core.Any = "mediaRuntime"

///|
extern "js" fn copy_bytes(value : @core.Any) -> @core.Any =
  #|value => new Uint8Array(value)

///|
fn release_canvas(canvas : @core.Any) -> Unit {
  canvas._set("width", @core.any(0))
  canvas._set("height", @core.any(0))
}

///|
fn new_canvas() -> @core.Any {
  @core.global_this()
  ._get("document")
  ._call("createElement", [@core.any("canvas")])
}
