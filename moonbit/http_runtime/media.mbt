///|
fn write_range(range : @policy.ByteRange) -> @core.Any {
  @core.from_entries([
    ("start", @core.any(range.start)),
    ("end", @core.any(range.end)),
  ])
}

///|
pub fn media_byte_range(header : String, size : Double) -> @core.Any {
  match @policy.byte_range(header, size) {
    Some(range) => write_range(range)
    None => @core.null()
  }
}

///|
pub fn image_headers(mime : String) -> @core.Any {
  headers_object(@policy.image_headers(mime))
}

///|
pub fn media_headers(mime : String, digest : String) -> @core.Any {
  headers_object(@policy.media_headers(mime, digest))
}

///|
pub fn media_response_plan(
  request : @core.Any,
  metadata : @core.Any,
  digest : String,
) -> @core.Any {
  let size : Double = metadata._get("size").cast()
  let response = @policy.media_response(
    optional_string(request._get("range")),
    optional_string(request._get("ifRange")),
    optional_string(request._get("ifNoneMatch")),
    size,
    digest,
  )
  let headers = media_headers(metadata._get("mime").cast(), digest)
  let status = match response {
    @policy.Cached => 304
    @policy.Unsatisfiable => 416
    @policy.Complete(_) => 200
    @policy.Partial(_) => 206
  }
  let result = @core.from_entries([
    ("status", @core.any(status)),
    ("headers", headers),
  ])
  match response {
    @policy.Cached => ()
    @policy.Unsatisfiable => {
      headers._set(
        "Content-Range",
        @core.any("bytes */" + native_number_string(size)),
      )
      headers._set("Content-Length", @core.any("0"))
    }
    @policy.Complete(range) | @policy.Partial(range) => {
      if status == 206 {
        headers._set(
          "Content-Range",
          @core.any(
            "bytes " +
            native_number_string(range.start) +
            "-" +
            native_number_string(range.end) +
            "/" +
            native_number_string(size),
          ),
        )
      }
      headers._set(
        "Content-Length",
        @core.any(native_number_string(range.end - range.start + 1.0)),
      )
      result._set("range", write_range(range))
    }
  }
  result
}
