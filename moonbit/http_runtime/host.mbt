///|
pub fn optional_string(value : @core.Any) -> String? {
  if @core.is_nullish(value) {
    None
  } else {
    Some(value.cast())
  }
}

///|
pub fn headers_object(values : Array[(String, String)]) -> @core.Any {
  @core.from_entries(values.map(fn(pair) { (pair.0, @core.any(pair.1)) }))
}

///|
pub fn native_error(error : Error) -> @core.Any {
  match error {
    UploadFailure(message, status) =>
      @core.new(media_error_type(), [@core.any(message), @core.any(status)])
    BodyFailure(message) =>
      @core.new(@core.global_this()._get("Error"), [@core.any(message)])
    @core.ThrowError(value) => value
    _ => @core.any(error)
  }
}

///|
pub fn[T] native_errors(promise : @core.Promise[T]) -> @core.Promise[T] {
  promise.catch_(fn(error) {
    @core.Promise::reject(native_error(error)).to_any().cast()
  })
}

///|
pub fn call_promise(
  value : @core.Any,
  method_ : String,
  args : FixedArray[@core.Any],
) -> @core.Promise[@core.Any] raise {
  @core.Promise::resolve(@core.throwable(fn() { value._call(method_, args) }))
}

///|
pub fn header(headers : @core.Any, name : String) -> String? {
  optional_string(headers._call("get", [@core.any(name)]))
}

///|
pub fn byte_header(value : @buffer.Uint8Array) -> Bytes {
  Bytes::makei(value.length().min(32), fn(index) {
    value.get_at(index).to_byte()
  })
}

///|
extern "js" fn bytes_slice(
  value : @buffer.Uint8Array,
  start : Int,
  end : Int,
) -> @buffer.Uint8Array =
  #|(value, start, end) => value.subarray(start, end)

///|
extern "js" fn copy_into(
  target : @buffer.Uint8Array,
  source : @buffer.Uint8Array,
  offset : Int,
) -> Unit =
  #|(target, source, offset) => target.set(source, offset)

///|
extern "js" fn native_number_string(value : Double) -> String =
  #|value => String(value)
