///|
// Registration is private to read_project after deep immutable capture.
// Caller-owned and in-transaction values always use the ordinary decoder.
let immutable_compositions : WeakCache[Unit] = WeakCache::new()

///|
let immutable_poses : WeakCache[@scene.ObjectState] = WeakCache::new()

///|
fn remember_composition_snapshot(value : @core.Any) -> Unit {
  immutable_compositions.set(value, ())
}

///|
fn decode_immutable_pose(value : @core.Any) -> @scene.ObjectState {
  if immutable_poses.has(value) {
    return immutable_poses.get(value)
  }
  // ObjectState and its nested Point/Bezier records are immutable values.
  // Public frame conversion still creates owned native state/path objects.
  let state = @project_codec.decode_ObjectState(value)
  immutable_poses.set(value, state)
  state
}

///|
fn decode_composition_snapshot(value : @core.Any) -> @scene.Composition {
  if immutable_compositions.has(value) {
    @project_codec.decode_Composition(
      value,
      state_decoder=decode_immutable_pose,
    )
  } else {
    @project_codec.decode_Composition(value)
  }
}
