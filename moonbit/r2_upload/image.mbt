///|
async fn put_image(
  bucket : @cf.R2Bucket,
  key : String,
  bytes : @buffer.Uint8Array,
  mime : String,
) -> @core.Any {
  if bytes.length() > @assets.image_limit {
    fail("画像データは 1 MB 以下にしてください。", status=413)
  }
  let detected = @assets.image_mime(@http.byte_header(bytes)[:])
  guard detected is Some(detected) && detected == mime else {
    fail("PNG・JPEG・WebP の画像を選択してください。")
    return @core.undefined()
  }
  let hash = create_hash("sha256")
  hash.update(bytes)
  let digest = hash.digest()
  try {
    let object = @cloud.put(
      bucket,
      key,
      bytes.as_any(),
      http_metadata(detected),
      digest,
    )
    if object.size() != bytes.length() {
      fail(
        "素材を保存できませんでした。もう一度お試しください。",
        status=502,
      )
    }
    uploaded(bytes.length(), detected, digest)
  } catch {
    error => raise storage_error(error)
  }
}

///|
pub fn upload_image(
  bucket : @cf.R2Bucket,
  key : String,
  bytes : @buffer.Uint8Array,
  mime : String,
) -> @core.Promise[@core.Any] {
  @core.from_async(async fn() { put_image(bucket, key, bytes, mime) })
  |> native_errors
}

///|
pub fn upload_image_request(
  bucket : @cf.R2Bucket,
  key : String,
  request : @core.Any,
) -> @core.Promise[@core.Any] {
  @core.from_async(async fn() {
    let scope = open_scope(request, Image)
    defer scope.close()
    try {
      scope.check()
      let expected = content_length(request, Image)
      let bytes = @buffer.Uint8Array::from_size(@assets.image_limit)
      let mut size = 0
      while true {
        let result = scope.read(Image)
        if (result._get("done").cast() : Bool) {
          break
        }
        let chunk : @buffer.Uint8Array = result._get("value").cast()
        let length : Double = chunk.as_any()._get("byteLength").cast()
        if length > (@assets.image_limit - size).to_double() {
          fail("画像データは 1 MB 以下にしてください。")
        }
        @core.throwable(fn() { copy(bytes, chunk, size) })
        size += length.to_int()
      }
      check_length(expected, size, Image)
      let image = slice(bytes, 0, size)
      guard @assets.image_mime(@http.byte_header(image)[:]) is Some(mime) else {
        fail("PNG・JPEG・WebP の画像を選択してください。")
        return @core.undefined()
      }
      scope.check()
      // Always settle an in-flight put before the caller retires this unique key.
      let result = put_image(bucket, key, image, mime)
      scope.check()
      result
    } catch {
      error => {
        scope.check()
        raise storage_error(error)
      }
    }
  })
  |> native_errors
}
