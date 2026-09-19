///|
pub fn asset_import_changes(
  scene : @core.Any,
  composition : String,
  assets : Array[@editor.PreparedAsset],
  point : @scene.Point?,
  start_override? : Double,
) -> @core.Any raise {
  let objects = scene._get("objects")
  let transitions = scene._get("transitions")
  let audio = scene._get("audioTracks")
  let order : FixedArray[String] = scene._get("compositionOrder").cast()
  let segments : FixedArray[@core.Any] = scene_segments(scene).cast()
  let start = segments
    .iter()
    .find_first(fn(segment) {
      @core.equal(segment._get("id"), @core.any(composition))
    })
    .map(fn(segment) { segment._get("start").cast() })
    .unwrap_or(0.0)
  let target : @editor.ImportScene = {
    width: scene._get("width").cast(),
    height: scene._get("height").cast(),
    orders: @core.object_keys(objects).map(fn(id) {
      objects._get(id)._get("order").cast()
    }),
    compositions: Array::makei(order.length(), fn(i) { order[i] }),
    transitions: @core.object_keys(transitions).map(fn(id) {
      (id, transitions._get(id)._get("duration").cast())
    }),
    start: start_override.unwrap_or(start),
    audio_count: if @core.is_nullish(audio) {
      None
    } else {
      Some(@core.object_keys(audio).length())
    },
  }
  let additions = match
    @editor.import_assets(target, composition, assets, point, new_id) {
    Ok(additions) => additions
    Err(message) => {
      @core.throwable(fn() { @core.throw_error(message) })
      return @core.undefined()
    }
  }
  let scene_id : String = scene._get("id").cast()
  let changes = object_insertion_changes(scene_id, additions.objects)
  let ids = additions.objects.map(fn(addition) { addition.object.id })
  for track in additions.audio {
    changes.push(
      make_change(
        ["scenes", scene_id, "audioTracks", track.id],
        encode_AudioTrack(track),
      ),
    )
  }
  @core.from_entries([
    ("ids", @core.any(FixedArray::from_array(ids[:]))),
    (
      "audioIds",
      @core.any(
        FixedArray::makei(additions.audio.length(), fn(i) {
          additions.audio[i].id
        }),
      ),
    ),
    ("changes", @core.any(FixedArray::from_array(changes[:]))),
  ])
}
