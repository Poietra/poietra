///|
/// An operation owns this validation table. Only immutable source strings are
/// shared; every native record and all its metadata are read and checked afresh.
pub struct AssetValidation {
  priv sources : @collection.JsMap[String, @assets.AssetKind]
}

///|
pub fn AssetValidation::new() -> AssetValidation {
  { sources: @collection.JsMap::new(), }
}

///|
fn AssetValidation::source(
  self : AssetValidation,
  source : String,
  kind : @assets.AssetKind,
) -> Bool {
  if self.sources.get(source) == Some(kind) {
    return true
  }
  if !@assets.valid_source(source, kind) {
    return false
  }
  self.sources.set(source, kind) |> ignore
  true
}

///|
fn AssetValidation::image(
  self : AssetValidation,
  asset : @scene.ImageAsset,
) -> Bool {
  @assets.valid_image_fields(asset.src, asset.width, asset.height) &&
  self.source(asset.src, @assets.Image)
}

///|
fn AssetValidation::media(
  self : AssetValidation,
  asset : @scene.MediaAsset,
) -> Bool {
  @assets.valid_media_fields(asset) && self.source(asset.src, @assets.Media)
}
