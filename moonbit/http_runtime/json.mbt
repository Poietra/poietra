///|
pub let ai_request_limit : Int = 262144

///|
pub fn read_json(
  request : @core.Any,
  maximum : Int,
) -> @core.Promise[@core.Any] {
  @core.from_async(async fn() {
    let body = request._get("body")
    if @core.is_nullish(body) {
      raise BodyFailure("Request body is missing")
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
      if chunk.length() > maximum - size {
        reader.cancel()
        raise BodyFailure("Request is too large")
      }
      copy_into(bytes, chunk, size)
      size += chunk.length()
    }
    let decoder = @core.new(@core.global_this()._get("TextDecoder"), [])
    let text = decoder._call("decode", [bytes_slice(bytes, 0, size).as_any()])
    @core.throwable(fn() {
      @core.global_this()._get("JSON")._call("parse", [text])
    })
  })
  |> native_errors
}
