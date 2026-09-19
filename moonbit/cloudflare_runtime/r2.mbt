// cloudflare.mbt's R2 awaits use moonbitlang/async's coroutine scheduler.
// Our HTTP handlers own native Promise lifetimes; bind those calls directly,
// retaining the upstream typed resources and option representations.

///|
pub async fn delete(bucket : @cf.R2Bucket, key : String) -> Unit {
  @http.call_promise(bucket.as_any(), "delete", [@core.any(key)]).wait()
  |> ignore
}

///|
pub async fn put(
  bucket : @cf.R2Bucket,
  key : String,
  value : @core.Any,
  metadata : @cf.R2HttpMetadata,
  digest : String,
) -> @cf.R2Object {
  @http.call_promise(bucket.as_any(), "put", [
    @core.any(key),
    value,
    @core.from_entries([
      ("httpMetadata", metadata.as_any()),
      ("sha256", @core.any(digest)),
    ]),
  ])
  .wait()
  .cast()
}

///|
pub async fn create_upload(
  bucket : @cf.R2Bucket,
  key : String,
  metadata : @cf.R2HttpMetadata,
) -> @cf.R2MultipartUpload {
  @http.call_promise(bucket.as_any(), "createMultipartUpload", [
    @core.any(key),
    @core.from_entries([("httpMetadata", metadata.as_any())]),
  ])
  .wait()
  .cast()
}

///|
pub async fn upload_part(
  upload : @cf.R2MultipartUpload,
  part : Int,
  value : @core.Any,
) -> @cf.R2UploadedPart {
  @http.call_promise(upload.as_any(), "uploadPart", [@core.any(part), value])
  .wait()
  .cast()
}

///|
pub async fn complete(
  upload : @cf.R2MultipartUpload,
  parts : Array[@cf.R2UploadedPart],
) -> @cf.R2Object {
  let values = FixedArray::makei(parts.length(), fn(i) { parts[i].as_any() })
  @http.call_promise(upload.as_any(), "complete", [@core.any(values)])
  .wait()
  .cast()
}

///|
pub async fn abort(upload : @cf.R2MultipartUpload) -> Unit {
  @http.call_promise(upload.as_any(), "abort", []).wait() |> ignore
}

///|
pub async fn get(
  bucket : @cf.R2Bucket,
  key : String,
  range : @cf.R2Range?,
) -> @cf.R2Object? {
  let options = match range {
    None => @core.undefined()
    Some(range) => {
      let fields = []
      if range.offset is Some(value) {
        fields.push(("offset", @core.any(value)))
      }
      if range.length is Some(value) {
        fields.push(("length", @core.any(value)))
      }
      if range.suffix is Some(value) {
        fields.push(("suffix", @core.any(value)))
      }
      @core.from_entries([("range", @core.from_entries(fields))])
    }
  }
  let result = @http.call_promise(bucket.as_any(), "get", [
    @core.any(key),
    options,
  ]).wait()
  if @core.is_nullish(result) {
    None
  } else {
    Some(result.cast())
  }
}
