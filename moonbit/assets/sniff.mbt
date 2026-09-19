///|
pub fn canonical_media_mime(mime : String) -> String {
  let value = mime.split(";").next().unwrap().trim().to_owned().to_lower()
  match value {
    "audio/x-wav" | "audio/wave" => "audio/wav"
    "audio/x-flac" => "audio/flac"
    "audio/x-m4a" => "audio/mp4"
    "audio/mp3" => "audio/mpeg"
    _ => value
  }
}

///|
fn signature(bytes : BytesView, start : Int, text : String) -> Bool {
  if bytes.length() < start + text.length() {
    return false
  }
  for index = 0; index < text.length(); index = index + 1 {
    if bytes[start + index].to_int() != text.code_unit_at(index).to_int() {
      return false
    }
  }
  true
}

///|
pub fn image_mime(bytes : BytesView) -> String? {
  if bytes.length() >= 24 && bytes[0:8] == b"\x89PNG\r\n\x1a\n"[:] {
    Some("image/png")
  } else if bytes.length() >= 4 &&
    bytes[0] == b'\xff' &&
    bytes[1] == b'\xd8' &&
    bytes[2] == b'\xff' {
    Some("image/jpeg")
  } else if bytes.length() >= 16 &&
    signature(bytes, 0, "RIFF") &&
    signature(bytes, 8, "WEBP") {
    Some("image/webp")
  } else {
    None
  }
}

///|
pub fn media_mime(bytes : BytesView, declared : String) -> String? {
  if signature(bytes, 0, "RIFF") && signature(bytes, 8, "WAVE") {
    return Some("audio/wav")
  }
  if bytes.length() >= 4 {
    if signature(bytes, 0, "fLaC") {
      return Some("audio/flac")
    }
    if signature(bytes, 0, "OggS") {
      return Some("audio/ogg")
    }
    let second = bytes[1].to_int()
    if signature(bytes, 0, "ID3") ||
      (
        bytes[0] == b'\xff' &&
        (second & 0xe0) == 0xe0 &&
        (second & 0x06) != 0 &&
        (second & 0x18) != 0x08
      ) {
      return Some("audio/mpeg")
    }
  }
  let mime = canonical_media_mime(declared)
  if signature(bytes, 4, "ftyp") &&
    [
      "isom", "iso2", "iso3", "iso4", "iso5", "iso6", "iso7", "iso8", "iso9", "mp41",
      "mp42", "avc1", "dash", "M4A ", "M4B ", "M4V ", "M4P ", "MSNV",
    ]
    .iter()
    .any(fn(brand) { signature(bytes, 8, brand) }) {
    return Some(if mime == "audio/mp4" { mime } else { "video/mp4" })
  }
  if bytes.length() >= 4 &&
    bytes[0] == b'\x1a' &&
    bytes[1] == b'E' &&
    bytes[2] == b'\xdf' &&
    bytes[3] == b'\xa3' {
    return Some(if mime == "audio/webm" { mime } else { "video/webm" })
  }
  None
}

///|
pub fn extension_mime(name : String) -> String {
  match name.split(".").last().unwrap().to_owned().to_lower() {
    "mp4" | "m4v" => "video/mp4"
    "mov" => "video/quicktime"
    "webm" => "video/webm"
    "mp3" => "audio/mpeg"
    "wav" => "audio/wav"
    "ogg" | "oga" => "audio/ogg"
    "flac" => "audio/flac"
    "m4a" => "audio/mp4"
    _ => ""
  }
}

///|
pub(all) enum ImportPhase {
  Reading
  Waveform
  Uploading
  Saving
}

///|
pub(all) enum MediaKind {
  Audio
  Video
}
