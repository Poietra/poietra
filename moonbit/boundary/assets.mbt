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
