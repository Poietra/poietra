///|
pub(all) enum AssetKind {
  Image
  Media
} derive(Eq)

///|
pub let image_limit : Int = 1048576

///|
pub let media_limit : Int = 33554432

///|
fn ascii_word(value : String) -> Bool {
  value
  .iter()
  .all(fn(c) {
    (c >= 'a' && c <= 'z') ||
    (c >= 'A' && c <= 'Z') ||
    (c >= '0' && c <= '9') ||
    c == '_' ||
    c == '-'
  })
}

///|
pub fn room_source(source : String, kind : AssetKind) -> Bool {
  if !source.has_prefix("/api/rooms/") {
    return false
  }
  let parts = source.split("/").map(fn(part) { part.to_owned() }).to_array()
  parts.length() == 6 &&
  parts[0] == "" &&
  parts[1] == "api" &&
  parts[2] == "rooms" &&
  parts[3].length() >= 16 &&
  parts[3].length() <= 80 &&
  ascii_word(parts[3]) &&
  parts[4] == (if kind == Image { "images" } else { "media" }) &&
  parts[5].length() == 64 &&
  parts[5]
  .iter()
  .all(fn(c) { (c >= 'a' && c <= 'f') || (c >= '0' && c <= '9') })
}

///|
pub fn data_source(source : String, kind : AssetKind) -> Bool {
  guard source.has_prefix("data:") && source.find(";base64,") is Some(separator) else {
    return false
  }
  let mime = source[5:separator].to_owned()
  let valid_mime = match kind {
    Image => ["image/png", "image/jpeg", "image/webp"].contains(mime)
    Media =>
      [
        "video/mp4", "video/webm", "audio/mpeg", "audio/wav", "audio/ogg", "audio/flac",
        "audio/mp4", "audio/webm",
      ].contains(mime)
  }
  if !valid_mime {
    return false
  }
  let start = separator + 8
  let mut end = source.length()
  let mut padding = 0
  while end > start && source.code_unit_at(end - 1) == 61 {
    padding += 1
    end -= 1
  }
  padding <= 2 &&
  end > start &&
  source[start:end]
  .iter()
  .all(fn(c) {
    (c >= 'a' && c <= 'z') ||
    (c >= 'A' && c <= 'Z') ||
    (c >= '0' && c <= '9') ||
    c == '+' ||
    c == '/'
  })
}

///|
pub fn valid_source(source : String, kind : AssetKind) -> Bool {
  room_source(source, kind) || data_source(source, kind)
}

///|
pub fn valid_image(source : String, width : Double, height : Double) -> Bool {
  source.length() <= 1398166 &&
  valid_source(source, Image) &&
  [width, height]
  .iter()
  .all(fn(size) {
    !size.is_nan() &&
    !size.is_inf() &&
    size >= 1.0 &&
    size <= 2048.0 &&
    size.trunc() == size
  })
}

///|
pub fn video_seconds(time : Double, duration : Double) -> Double {
  @scene.maximum(0.0, @scene.minimum(time, duration - 0.001)) / 1000.0
}
