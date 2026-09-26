///|
// Only read_project registers these captured, deeply immutable Scene snapshots.
// Object.isFrozen on a caller's object cannot establish that ownership: nested
// values or accessors may still change. Transaction-local reads stay unregistered.
let immutable_scenes : WeakCache[Unit] = WeakCache::new()

///|
let object_layouts : WeakCache[@scene.ObjectLayout] = WeakCache::new()

///|
fn remember_scene_snapshot(value : @core.Any) -> Unit {
  immutable_scenes.set(value, ())
}

///|
fn decode_ordered_objects(input : @core.Any) -> Array[@scene.SceneObject] {
  ordered_objects(input)
  .iter()
  .map(@project_codec.decode_SceneObject)
  .to_array()
}

///|
fn composition_objects(
  input : @core.Any,
  composition : @scene.Composition,
  time : Double,
) -> Array[@scene.RenderObject] {
  if !immutable_scenes.has(input) {
    return @scene.composition_objects(
      decode_ordered_objects(input),
      composition,
      time,
    )
  }
  // Pose edits retain the object map identity. Reorder, metadata, kind and parent
  // edits replace that branch before observers; weak keys bound cache lifetime.
  let objects = input._get("objects")
  let layout = if object_layouts.has(objects) {
    object_layouts.get(objects)
  } else {
    let layout = @scene.ObjectLayout::new(decode_ordered_objects(input))
    object_layouts.set(objects, layout)
    layout
  }
  layout.evaluate(composition, time)
}
