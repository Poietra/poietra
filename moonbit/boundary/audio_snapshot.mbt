///|
// Entries are validated typed captures, never merely trusted because frozen.
// Weak keys follow the immutable native media leaf, which survives clip edits.
let validated_audio_assets : WeakCache[@scene.MediaAsset] = WeakCache::new()

///|
pub fn validate_audio_track_edit(
  scene : @core.Any,
  id : String,
  patch : @core.Any,
) -> Unit raise {
  let current = scene._get("audioTracks")._get(id)
  let previous_asset = current._get("asset")
  let trusted = immutable_scenes.has(scene)
  @project_codec.read_audio_track(merge_values(current, patch), media_reader=fn(
    value,
  ) raise {
    // A caller's patch can replace the asset, even when the current Scene is
    // trusted. Only the original captured leaf is eligible for shared reads.
    if !trusted || !strict_equal(value, previous_asset) {
      return @project_codec.read_media_asset(value)
    }
    if validated_audio_assets.has(value) {
      return validated_audio_assets.get(value)
    }
    let asset = @project_codec.read_media_asset(value)
    validated_audio_assets.set(value, asset)
    asset
  })
  |> ignore
}
