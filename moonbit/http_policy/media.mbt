///|
pub(all) struct ByteRange {
  start : Double
  end : Double
} derive(Eq)

///|
fn unsigned_safe_integer(value : StringView) -> Double? {
  if value.is_empty() {
    return None
  }
  let mut result = 0.0
  for index = 0; index < value.length(); index = index + 1 {
    let digit = value.code_unit_at(index).to_int() - 48
    if digit < 0 || digit > 9 {
      return None
    }
    result = result * 10.0 + digit.to_double()
    if result > 9007199254740991.0 {
      return None
    }
  }
  Some(result)
}

///|
pub fn byte_range(header : String, size : Double) -> ByteRange? {
  let header = @editor.trim_text(header).to_owned().to_lower()
  if !header.has_prefix("bytes=") || size <= 0.0 {
    return None
  }
  let bounds = header[6:].split("-").to_array()
  if bounds.length() != 2 {
    return None
  }
  if bounds[0].is_empty() {
    guard unsigned_safe_integer(bounds[1]) is Some(length) && length > 0.0 else {
      return None
    }
    return Some({ start: (size - length).max(0.0), end: size - 1.0, })
  }
  guard unsigned_safe_integer(bounds[0]) is Some(start) else { return None }
  let end = if bounds[1].is_empty() {
    Some(size - 1.0)
  } else {
    unsigned_safe_integer(bounds[1])
  }
  guard end is Some(end) && start < size && end >= start else { return None }
  Some({ start, end: end.min(size - 1.0), })
}

///|
pub fn image_headers(mime : String) -> Array[(String, String)] {
  [
    ("Content-Type", mime),
    ("Cache-Control", "private, max-age=31536000, immutable"),
    ("X-Content-Type-Options", "nosniff"),
    ("Content-Security-Policy", "default-src 'none'"),
    ("Cross-Origin-Resource-Policy", "same-origin"),
  ]
}

///|
pub fn media_headers(mime : String, digest : String) -> Array[(String, String)] {
  let headers = image_headers(mime)
  headers.push(("Accept-Ranges", "bytes"))
  headers.push(("ETag", "\"" + digest + "\""))
  headers
}

///|
pub(all) enum MediaResponse {
  Cached
  Unsatisfiable
  Complete(ByteRange)
  Partial(ByteRange)
}

///|
pub fn media_response(
  range : String?,
  if_range : String?,
  if_none_match : String?,
  size : Double,
  digest : String,
) -> MediaResponse {
  let etag = "\"" + digest + "\""
  if if_none_match is Some(header) {
    for value in header.split(",") {
      let value = @editor.trim_text(value.to_owned())
      if value == "*" ||
        value == etag ||
        (value.has_prefix("W/") && value[2:] == etag) {
        return Cached
      }
    }
  }
  if range is Some(header) &&
    !header.is_empty() &&
    @editor.trim_text(header).to_owned().to_lower().has_prefix("bytes=") &&
    (if_range is None || if_range == Some("") || if_range == Some(etag)) {
    return match byte_range(header, size) {
      Some(range) => Partial(range)
      None => Unsatisfiable
    }
  }
  Complete({ start: 0.0, end: size - 1.0, })
}
