///|
fn chunks_table(kind : @assets.AssetKind) -> String {
  match kind {
    Image => "image_chunks"
    Media => "media_chunks"
  }
}

///|
fn Room::legacy_body(
  self : Room,
  kind : @assets.AssetKind,
  digest : String,
  start : Int,
  end : Int,
) -> @core.Any {
  let mut offset = start
  @core.new(@core.global_this()._get("ReadableStream"), [
    @core.from_entries([
      (
        "pull",
        @core.any(fn(controller : @core.Any) {
          if offset > end {
            controller._call("close", []) |> ignore
            return
          }
          let part = offset / 131072
          let rows = self.sql
            .exec2(
              "SELECT data FROM " +
              chunks_table(kind) +
              " WHERE id = ? AND part = ?",
              @core.any(digest),
              @core.any(part),
            )
            .to_array()
          if rows.is_empty() {
            controller._call("error", [
              @core.new(@core.global_this()._get("Error"), [
                @core.any("Incomplete legacy asset"),
              ]),
            ])
            |> ignore
            return
          }
          let begin = offset % 131072
          let bytes = @buffer.Uint8Array::from_array_buffer(
            rows[0]._get("data").cast(),
          )
          let chunk = bytes
            .as_any()
            ._call("subarray", [
              @core.any(begin),
              @core.any(bytes.length().min(begin + end - offset + 1)),
            ])
          let size : Int = chunk._get("byteLength").cast()
          if size == 0 {
            controller._call("error", [
              @core.new(@core.global_this()._get("Error"), [
                @core.any("Incomplete legacy asset"),
              ]),
            ])
            |> ignore
            return
          }
          offset += size
          controller._call("enqueue", [chunk]) |> ignore
        }),
      ),
    ]),
  ])
}

///|
async fn Room::copy_legacy(
  self : Room,
  room : String,
  kind : @assets.AssetKind,
  digest : String,
  mime : String,
  size : Int,
) -> Unit {
  let token = kind.name() + "/" + digest
  defer self.promoting.remove(token) |> ignore
  let mut key : String? = None
  defer (if key is Some(key) {
    @http.call_promise(self.assets, "discard", [@core.any(key)]).wait()
    |> ignore
  })
  try {
    let reserved = asset_value(
      @http.call_promise(self.assets, "begin", [
        @core.any(room),
        @core.any(kind.name()),
      ]).wait(),
    )
    let upload_key : String = reserved.cast()
    key = Some(upload_key)
    let request = @core.new(@core.global_this()._get("Request"), [
      @core.any("https://assets.internal/"),
      @core.from_entries([
        ("method", @core.any("POST")),
        (
          "headers",
          @http.headers_object([
            ("Content-Type", mime),
            ("Content-Length", "\{size}"),
          ]),
        ),
        ("body", self.legacy_body(kind, digest, 0, size - 1)),
      ]),
    ])
    let bucket : @cf.R2Bucket = self.env._get("MEDIA_BUCKET").cast()
    let metadata = match kind {
      Image => {
        let bytes = @http.read_image_body(request.cast()).wait()
        guard @assets.image_mime(@http.byte_header(bytes)[:]) is Some(detected) else {
          fail("Invalid legacy image")
          panic()
        }
        @upload.upload_image(bucket, upload_key, bytes, detected).wait()
      }
      Media => @upload.upload_media(bucket, upload_key, request).wait()
    }
    if string(metadata, "digest") != digest ||
      (metadata._get("size").cast() : Int) != size {
      fail("Legacy asset checksum mismatch")
    }
    asset_value(
      self.assets._call("finish", [
        reserved,
        metadata._get("digest"),
        metadata._get("mime"),
        metadata._get("size"),
      ]),
    )
    |> ignore
    // Keep old chunks as a fallback during the first rollout.
  } catch {
    _ =>
      @core.global_this()
      ._get("console")
      ._call("warn", [@core.any("asset_legacy_copy_retry")])
      |> ignore
  }
}

///|
fn Room::promote_legacy(
  self : Room,
  room : String,
  kind : @assets.AssetKind,
  digest : String,
  mime : String,
  size : Int,
) -> Unit {
  let token = kind.name() + "/" + digest
  let metadata = self.assets._call("get", [
    @core.any(kind.name()),
    @core.any(digest),
  ])
  if self.promoting.contains(token) ||
    (
      !@core.is_nullish(metadata) &&
      !@core.is_nullish(metadata._get("objectKey"))
    ) {
    return
  }
  self.promoting.add(token) |> ignore
  let task = @core.from_async(async fn() {
      self.copy_legacy(room, kind, digest, mime, size)
    })
    |> @http.native_errors
  self.ctx._call("waitUntil", [task.to_any()]) |> ignore
}

///|
async fn Room::save_image(
  self : Room,
  room : String,
  bytes : @buffer.Uint8Array,
  mime : String,
) -> String {
  let key = asset_value(
    @http.call_promise(self.assets, "begin", [
      @core.any(room),
      @core.any("images"),
    ]).wait(),
  )
  defer @http.call_promise(self.assets, "discard", [key]).wait() |> ignore
  let metadata = @upload.upload_image(
    self.env._get("MEDIA_BUCKET").cast(),
    key.cast(),
    bytes,
    mime,
  ).wait()
  asset_value(
    self.assets._call("finish", [
      key,
      metadata._get("digest"),
      metadata._get("mime"),
      metadata._get("size"),
    ]),
  )
  |> ignore
  "/api/rooms/" + room + "/images/" + string(metadata, "digest")
}

///|
fn Room::legacy_response(
  self : Room,
  request : @core.Any,
  route : @assets.AssetRoute,
) -> @core.Any {
  let method_ = string(request, "method")
  guard route.digest is Some(digest) && (method_ == "GET" || method_ == "HEAD") else {
    return error_response("Method not allowed", 405)
  }
  let kind = route.kind
  let name = match kind {
    Image => "画像"
    Media => "音声・動画"
  }
  let rows = self.sql
    .exec1(
      "SELECT mime, size FROM " + kind.name() + " WHERE id = ?",
      @core.any(digest),
    )
    .to_array()
  if rows.is_empty() {
    return error_response(name + "が見つかりません。", 404)
  }
  let metadata = rows[0]
  let mime = string(metadata, "mime")
  let size : Int = metadata._get("size").cast()
  let (headers, status, start, end) = match kind {
    Image => {
      let headers = @http.image_headers(mime)
      headers._set("Content-Length", @core.any("\{size}"))
      headers._set("ETag", @core.any("\"" + digest + "\""))
      (headers, 200, 0, size - 1)
    }
    Media => {
      let input_headers = request._get("headers")
      let plan = @http.media_response_plan(
        @core.from_entries([
          (
            "range",
            if method_ == "GET" {
              input_headers._call("get", [@core.any("Range")])
            } else {
              @core.null()
            },
          ),
          ("ifRange", input_headers._call("get", [@core.any("If-Range")])),
          (
            "ifNoneMatch",
            input_headers._call("get", [@core.any("If-None-Match")]),
          ),
        ]),
        metadata,
        digest,
      )
      let status : Int = plan._get("status").cast()
      let range = plan._get("range")
      if @core.is_nullish(range) || method_ == "HEAD" {
        return response(@core.null(), status~, headers=plan._get("headers"))
      }
      (
        plan._get("headers"),
        status,
        (range._get("start").cast() : Int),
        (range._get("end").cast() : Int),
      )
    }
  }
  if method_ == "HEAD" {
    return response(@core.null(), status~, headers~)
  }
  if self.sql
    .exec1(
      "SELECT id FROM " + chunks_table(kind) + " WHERE id = ? LIMIT 1",
      @core.any(digest),
    )
    .to_array()
    .is_empty() {
    return error_response(
      name +
      "を読み込めませんでした。再試行してください。",
      503,
    )
  }
  self.promote_legacy(route.room, kind, digest, mime, size)
  response(self.legacy_body(kind, digest, start, end), status~, headers~)
}
