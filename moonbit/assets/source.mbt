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
pub fn valid_room(value : String) -> Bool {
  value.length() >= 16 && value.length() <= 80 && ascii_word(value)
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
  valid_room(parts[3]) &&
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
  valid_image_fields(source, width, height) && valid_source(source, Image)
}

///|
/// Metadata checks remain per reference when the immutable source was checked.
pub fn valid_image_fields(
  source : String,
  width : Double,
  height : Double,
) -> Bool {
  source.length() <= image_data_limit &&
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

///|
/// The longest inline image reference: a 1 MiB file as a base64 data URL.
pub let image_data_limit : Int = 1398166

///|
/// Figures pasted into one Codex request.
pub let figure_limit : Int = 2

///|
fn base64_value(c : Int) -> Int {
  if c >= 65 && c <= 90 {
    c - 65
  } else if c >= 97 && c <= 122 {
    c - 71
  } else if c >= 48 && c <= 57 {
    c + 4
  } else if c == 43 {
    62
  } else {
    63
  }
}

///|
/// A pasted figure travels inline to the model only. Its declared type must
/// match the decoded signature and its bytes must fit one stored image.
pub fn figure_mime(source : String) -> String? {
  guard source.length() <= image_data_limit &&
    data_source(source, Image) &&
    source.find(";base64,") is Some(separator) else {
    return None
  }
  let start = separator + 8
  let mut padding = 0
  while padding < 2 && source.code_unit_at(source.length() - 1 - padding) == 61 {
    padding += 1
  }
  let encoded = source.length() - start
  if encoded % 4 != 0 || encoded / 4 * 3 - padding > image_limit || encoded < 32 {
    return None
  }
  // 32 characters decode to the 24 bytes the image signatures need.
  let header = Array::make(24, b'\x00')
  for group = 0; group < 8; group = group + 1 {
    let mut bits = 0
    for i = 0; i < 4; i = i + 1 {
      bits = (bits << 6) |
        base64_value(source.code_unit_at(start + group * 4 + i).to_int())
    }
    header[group * 3] = (bits >> 16).to_byte()
    header[group * 3 + 1] = ((bits >> 8) & 255).to_byte()
    header[group * 3 + 2] = (bits & 255).to_byte()
  }
  let declared = source[5:separator].to_owned()
  match image_mime(Bytes::from_array(header)[:]) {
    Some(mime) if mime == declared => Some(mime)
    _ => None
  }
}
