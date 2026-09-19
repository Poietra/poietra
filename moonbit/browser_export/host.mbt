///|
priv suberror ExportFailure {
  Invalid(String)
  Native(@core.Any)
}

///|
fn native_error(error : Error) -> @core.Any {
  match error {
    Invalid(message) =>
      @core.new(@core.global_this()._get("Error"), [@core.any(message)])
    Native(value) | @core.ThrowError(value) => value
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
fn aborted(signal : @core.Any) -> Bool {
  !@core.is_nullish(signal) && signal._get("aborted").cast()
}

///|
pub fn export_abort_error() -> @core.Any {
  @core.new(@core.global_this()._get("DOMException"), [
    @core.any("動画の書き出しをキャンセルしました。"),
    @core.any("AbortError"),
  ])
}

///|
fn check_signal(signal : @core.Any) -> Unit raise ExportFailure {
  if aborted(signal) {
    raise Native(export_abort_error())
  }
}

///|
extern "js" fn native_throw(error : @core.Any) -> Unit =
  #|error => { throw error; }

///|
pub fn check_abort(signal : @core.Any) -> Unit {
  if aborted(signal) {
    native_throw(export_abort_error())
  }
}

///|
pub fn abortable(
  promise : @core.Promise[@core.Any],
  signal : @core.Any,
) -> @core.Promise[@core.Any] {
  if @core.is_nullish(signal) {
    return promise
  }
  let completion : @core.PromiseResolvers[@core.Any] = @core.Promise::withResolvers()
  let abort_ref : Ref[(() -> Unit)?] = Ref(None)
  let cleanup = fn() {
    if abort_ref.val is Some(abort) {
      signal._call("removeEventListener", [@core.any("abort"), @core.any(abort)])
      |> ignore
      abort_ref.val = None
    }
  }
  let abort = fn() {
    cleanup()
    completion.reject(export_abort_error().cast())
  }
  abort_ref.val = Some(abort)
  signal._call("addEventListener", [
    @core.any("abort"),
    @core.any(abort),
    @core.from_entries([("once", @core.any(true))]),
  ])
  |> ignore
  promise
  .then(fn(value) {
    cleanup()
    completion.resolve(value)
    @core.Promise::resolve(())
  })
  .catch_(fn(error) {
    cleanup()
    completion.reject(native_error(error).cast())
    @core.Promise::resolve(())
  })
  |> ignore
  if aborted(signal) {
    abort()
  }
  completion.promise
}

///|
#module("#poietra/media-host")
extern "js" fn video_probe_runtime() -> @core.Any = "videoProbeRuntime"

///|
#module("#poietra/media-host")
extern "js" fn encoder_runtime() -> @core.Any = "encoderRuntime"

///|
#module("#poietra/media-host")
extern "js" fn audio_encoder_runtime() -> @core.Any = "audioEncoderRuntime"

///|
extern "js" fn snapshot(value : @core.Any) -> @core.Any =
  #|value => structuredClone(value)

///|
extern "js" fn shallow_copy(value : @core.Any) -> @core.Any =
  #|value => ({ ...value })

///|
fn optional_double(value : @core.Any) -> Double? {
  if @core.is_nullish(value) {
    None
  } else {
    Some(value.cast())
  }
}

///|
async fn invoke(
  owner : @core.Any,
  operation : String,
  args : FixedArray[@core.Any],
) -> @core.Any {
  let value = @core.throwable(fn() { owner._call(operation, args) })
  @core.Promise::resolve(value).wait()
}
