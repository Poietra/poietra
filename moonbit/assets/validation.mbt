///|
pub fn bounded_number(
  value : Double,
  minimum : Double,
  maximum : Double,
) -> Bool {
  !value.is_nan() && !value.is_inf() && value >= minimum && value <= maximum
}

///|
pub fn document_id(value : String) -> Bool {
  value.length() >= 1 &&
  value.length() <= 80 &&
  ascii_word(value) &&
  value != "__proto__" &&
  value != "constructor" &&
  value != "prototype"
}

///|
pub fn document_color(value : String) -> Bool {
  value == "none" ||
  value == "transparent" ||
  (
    (value.length() == 4 || value.length() == 7 || value.length() == 9) &&
    value.code_unit_at(0) == 35 &&
    value[1:]
    .iter()
    .all(fn(c) {
      (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F')
    })
  )
}

///|
pub fn valid_media(asset : @scene.MediaAsset) -> Bool {
  if asset.src.length() > 44739307 ||
    !valid_source(asset.src, Media) ||
    ![
      "video/mp4", "video/webm", "audio/mpeg", "audio/wav", "audio/ogg", "audio/flac",
      "audio/mp4", "audio/webm",
    ].contains(asset.mime) ||
    !bounded_number(asset.duration, 0.0, 86400000.0) ||
    asset.duration <= 0.0 {
    return false
  }
  if asset.src.has_prefix("data:") &&
    !asset.src.has_prefix("data:" + asset.mime + ";") {
    return false
  }
  for size in [asset.width, asset.height] {
    if size is Some(value) &&
      (!bounded_number(value, 1.0, 8192.0) || value.trunc() != value) {
      return false
    }
  }
  if asset.mime.has_prefix("video/") &&
    (asset.width is None || asset.height is None) {
    return false
  }
  if asset.waveform is Some(waveform) &&
    (
      waveform.length() > 160 ||
      !waveform.iter().all(fn(value) { bounded_number(value, 0.0, 1.0) })
    ) {
    return false
  }
  true
}

///|
pub fn valid_playback(value : @scene.MediaPlayback) -> Bool {
  [value.start, value.offset, value.duration]
  .iter()
  .all(fn(value) { bounded_number(value, 0.0, 86400000.0) })
}

///|
pub fn valid_audio(track : @scene.AudioTrack) -> Bool {
  document_id(track.id) &&
  track.name.length() <= 200 &&
  valid_media(track.asset) &&
  track.asset.hasAudio &&
  bounded_number(track.volume, 0.0, 1.0) &&
  valid_playback({
    start: track.start,
    offset: track.offset,
    duration: track.duration,
  }) &&
  track.offset + track.duration <= track.asset.duration + 1.0
}
