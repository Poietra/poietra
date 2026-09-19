///|
priv suberror BodyFailure {
  BodyFailure(String)
}

///|
priv suberror UploadFailure {
  UploadFailure(String, Int)
}

///|
#module("#poietra/http-host")
extern "js" fn error_class(fields : (@core.Any) -> @core.Any) -> @core.Any = "uploadErrorClass"

///|
let upload_error_class : @core.Any = error_class(fn(status) {
  @core.from_entries([
    (
      "status",
      if @core.typeof_(status) == "undefined" {
        @core.any(400)
      } else {
        status
      },
    ),
  ])
})

///|
pub fn media_error_type() -> @core.Any {
  upload_error_class
}

///|
pub fn image_digest(bytes : @core.Any) -> @core.Promise[String] {
  @core.from_async(async fn() {
    let digest = @buffer.Uint8Array::from_array_buffer(
      @crypto.Crypto::get().subtle.digest("SHA-256", bytes),
    )
    let hex = "0123456789abcdef"
    let text = StringBuilder()
    for index = 0; index < digest.length(); index = index + 1 {
      let value = digest.get_at(index)
      text.write_string(hex[value / 16:value / 16 + 1].to_owned())
      text.write_string(hex[value % 16:value % 16 + 1].to_owned())
    }
    text.to_string()
  })
  |> native_errors
}

///|
/// Coalesce immediately: even one-byte network chunks cannot grow a chunk list.
pub fn read_image_body(
  request : @core.Any,
) -> @core.Promise[@buffer.Uint8Array] {
  @core.from_async(async fn() {
    let body = request._get("body")
    if @core.is_nullish(body) {
      raise BodyFailure("画像がありません。")
    }
    let stream : @streams.ReadableStream = body.cast()
    let reader = @core.throwable(fn() { stream.get_reader() })
    defer reader.release_lock()
    let bytes = @buffer.Uint8Array::from_size(1024 * 1024)
    let mut size = 0
    while true {
      let result = reader.read()
      if (result._get("done").cast() : Bool) {
        break
      }
      let chunk : @buffer.Uint8Array = result._get("value").cast()
      let length : Double = chunk.as_any()._get("byteLength").cast()
      if length > (1024 * 1024 - size).to_double() {
        reader.cancel()
        raise BodyFailure(
          "画像データは 1 MB 以下にしてください。",
        )
      }
      @core.throwable(fn() { copy_into(bytes, chunk, size) })
      size += length.to_int()
    }
    let result = bytes_slice(bytes, 0, size)
    if @assets.image_mime(byte_header(result)[:]) is None {
      raise BodyFailure(
        "PNG・JPEG・WebP の画像を選択してください。",
      )
    }
    result
  })
  |> native_errors
}

///|
extern "js" fn async_iterator(input : @core.Any) -> @core.Any =
  #|input => (input[Symbol.asyncIterator] ?? input[Symbol.iterator]).call(input)

///|
async fn close_iterator(iterator : @core.Any) -> Unit {
  try {
    if @core.typeof_(iterator._get("return")) == "function" {
      call_promise(iterator, "return", []).wait() |> ignore
    }
  } catch {
    _ => ()
  }
}

///|
priv struct ChunkWriter {
  bytes : @buffer.Uint8Array
  write : (@buffer.Uint8Array, Int) -> @core.Any
  declared : String
  mut filled : Int
  mut part : Int
  mut mime : String?
}

///|
async fn ChunkWriter::flush(self : ChunkWriter) -> Unit {
  let chunk = bytes_slice(self.bytes, 0, self.filled)
  if self.mime is None {
    self.mime = @assets.media_mime(byte_header(chunk)[:], self.declared)
    if self.mime is None {
      raise UploadFailure(
        "対応する音声・動画ファイルを選択してください。",
        400,
      )
    }
  }
  @core.Promise::resolve(
    @core.throwable(fn() { (self.write)(chunk, self.part) }),
  ).wait()
  |> ignore
  // The sink has consumed the bytes before reuse; at most one write is in flight.
  self.part += 1
  self.filled = 0
}

///|
pub fn write_media_chunks(
  input : @core.Any,
  declared : String,
  content_length : @core.Any,
  write : (@buffer.Uint8Array, Int) -> @core.Any,
) -> @core.Promise[@core.Any] {
  @core.from_async(async fn() {
    if !@core.is_nullish(content_length) {
      let length : Double = @core.global_this()
        ._call("Number", [content_length])
        .cast()
      if length > 33554432.0 {
        raise UploadFailure(
          "音声・動画は 32 MB 以下にしてください。", 413,
        )
      }
    }
    let writer : ChunkWriter = {
      bytes: @buffer.Uint8Array::from_size(131072),
      write,
      declared,
      filled: 0,
      part: 0,
      mime: None,
    }
    let iterator = @core.throwable(fn() { async_iterator(input) })
    let mut size = 0
    while true {
      let step = call_promise(iterator, "next", []).wait()
      if (step._get("done").cast() : Bool) {
        break
      }
      errdefer close_iterator(iterator)
      let chunk : @buffer.Uint8Array = step._get("value").cast()
      let length : Double = chunk.as_any()._get("byteLength").cast()
      if length > (33554432 - size).to_double() {
        raise UploadFailure(
          "音声・動画は 32 MB 以下にしてください。", 413,
        )
      }
      size += length.to_int()
      let mut offset = 0
      while offset < chunk.length() {
        let count = (131072 - writer.filled).min(chunk.length() - offset)
        @core.throwable(fn() {
          copy_into(
            writer.bytes,
            bytes_slice(chunk, offset, offset + count),
            writer.filled,
          )
        })
        writer.filled += count
        offset += count
        if writer.filled == 131072 {
          writer.flush()
        }
      }
    }
    if writer.filled > 0 {
      writer.flush()
    }
    guard writer.mime is Some(mime) && size > 0 else {
      raise UploadFailure(
        "空の音声・動画ファイルは追加できません。", 400,
      )
    }
    @core.from_entries([("size", @core.any(size)), ("mime", @core.any(mime))])
  })
  |> native_errors
}
