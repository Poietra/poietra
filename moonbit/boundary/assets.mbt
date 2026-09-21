///|
fn asset_header(value : @core.Any) -> Bytes {
  let bytes : FixedArray[Int] = value.cast()
  Bytes::makei(bytes.length().min(32), fn(index) { bytes[index].to_byte() })
}

///|
pub fn canonical_media_mime(value : String) -> String {
  @assets.canonical_media_mime(value)
}

///|
pub fn media_mime(bytes : @core.Any, declared : @core.Any) -> @core.Any {
  match
    @assets.media_mime(
      asset_header(bytes)[:],
      if @core.is_nullish(declared) {
        ""
      } else {
        declared.cast()
      },
    ) {
    Some(value) => @core.any(value)
    None => @core.null()
  }
}

///|
pub fn image_mime(bytes : @core.Any) -> @core.Any {
  match @assets.image_mime(asset_header(bytes)[:]) {
    Some(value) => @core.any(value)
    None => @core.null()
  }
}

///|
pub fn read_image_asset(value : @core.Any) -> @scene.ImageAsset raise {
  @project_codec.read_image_asset(value)
}

///|
pub fn read_media_asset(value : @core.Any) -> @scene.MediaAsset raise {
  @project_codec.read_media_asset(value)
}

///|
pub fn write_image_asset(value : @scene.ImageAsset) -> @core.Any {
  @project_codec.encode_ImageAsset(value)
}

///|
pub fn write_media_asset(value : @scene.MediaAsset) -> @core.Any {
  @project_codec.encode_MediaAsset(value)
}

///|
pub fn read_media_playback(value : @core.Any) -> @scene.MediaPlayback raise {
  @project_codec.read_media_playback(value)
}

///|
pub fn read_audio_track(value : @core.Any) -> @scene.AudioTrack raise {
  @project_codec.read_audio_track(value)
}

///|
pub fn write_media_playback(value : @scene.MediaPlayback) -> @core.Any {
  @project_codec.encode_MediaPlayback(value)
}
