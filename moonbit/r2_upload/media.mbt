///|
priv struct Multipart {
  upload : @cf.R2MultipartUpload
  bytes : @buffer.Uint8Array
  parts : Array[@cf.R2UploadedPart]
  mut filled : Int
}

///|
async fn Multipart::flush(self : Multipart, scope : UploadScope) -> Unit {
  if self.filled == 0 {
    return
  }
  scope.check()
  self.parts.push(
    @cloud.upload_part(
      self.upload,
      self.parts.length() + 1,
      slice(self.bytes, 0, self.filled).as_any(),
    ),
  )
  scope.check()
  // Exactly one 5 MiB buffer; R2 has consumed it before it is reused.
  self.filled = 0
}

///|
extern "js" fn iterator(next : () -> @core.Promise[@core.Any]) -> @core.Any =
  #|next => ({ [Symbol.asyncIterator]() { return this; }, next })

///|
pub fn upload_media(
  bucket : @cf.R2Bucket,
  key : String,
  request : @core.Any,
) -> @core.Promise[@core.Any] {
  @core.from_async(async fn() {
    let scope = open_scope(request, Media)
    defer scope.close()
    let current : Ref[Multipart?] = Ref(None)
    try {
      scope.check()
      let expected = content_length(request, Media)
      let declared = @http.header(request._get("headers"), "Content-Type").unwrap_or(
        "",
      )
      let hash = create_hash("sha256")
      let input = iterator(fn() {
        @core.from_async(async fn() { scope.read(Media) }) |> native_errors
      })
      let metadata = @http.write_media_chunks(input, declared, @core.null(), fn(
        chunk,
        _part,
      ) {
        @core.from_async(async fn() {
          scope.check()
          if current.val is None {
            let mime = @assets.media_mime(@http.byte_header(chunk)[:], declared).unwrap()
            let upload = @cloud.create_upload(bucket, key, http_metadata(mime))
            current.val = Some({
              upload,
              bytes: @buffer.Uint8Array::from_size(5242880),
              parts: [],
              filled: 0,
            })
            scope.check()
          }
          let session = current.val.unwrap()
          hash.update(chunk)
          let mut offset = 0
          while offset < chunk.length() {
            let count = (5242880 - session.filled).min(chunk.length() - offset)
            @core.throwable(fn() {
              copy(
                session.bytes,
                slice(chunk, offset, offset + count),
                session.filled,
              )
            })
            session.filled += count
            offset += count
            if session.filled == 5242880 {
              session.flush(scope)
            }
          }
        }).to_any()
      }).wait()
      let size : Int = metadata._get("size").cast()
      check_length(expected, size, Media)
      scope.check()
      guard current.val is Some(session) else {
        fail("空の音声・動画ファイルは追加できません。")
        return @core.undefined()
      }
      session.flush(scope)
      scope.check()
      let completed = @cloud.complete(session.upload, session.parts)
      scope.check()
      if completed.size() != size {
        fail(
          "素材を保存できませんでした。もう一度お試しください。",
          status=502,
        )
      }
      uploaded(size, metadata._get("mime").cast(), hash.digest())
    } catch {
      error => {
        scope.cancel().wait()
        if current.val is Some(session) {
          @cloud.abort(session.upload) catch {
            _ =>
              @core.global_this()
              ._get("console")
              ._call("warn", [
                @core.any("{\"event\":\"r2_multipart_abort_failed\"}"),
              ])
              |> ignore
          }
        }
        scope.check()
        raise storage_error(error)
      }
    }
  })
  |> native_errors
}
