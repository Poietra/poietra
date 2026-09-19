///|
/// Opaque compiled handle. Its fields are private even to MoonBit consumers.
pub struct Playback {
  priv program : @scene.PreparedScene
  priv source : @core.Any
}

///|
extern "js" fn snapshot(value : @core.Any) -> @core.Any =
  #|(value) => structuredClone(value)

///|
pub fn prepare_playback(input : @core.Any, host : @core.Any) -> Playback {
  let source = snapshot(input)
  { program: @scene.prepare_scene(decode_Scene(source), kernel(host)), source, }
}

///|
pub fn playback_frame(playback : Playback, time : Double) -> @core.Any {
  frame_value(playback.program.evaluate(time), playback.source)
}

///|
pub fn playback_composition(
  playback : Playback,
  id : String,
  time : @core.Any,
) -> @core.Any {
  frame_value(
    playback.program.composition(id, optional(time, fn(value) { value.cast() })),
    playback.source,
  )
}

///|
pub fn playback_transition(
  playback : Playback,
  id : String,
  time : Double,
  scene_time : @core.Any,
) -> @core.Any {
  frame_value(
    playback.program.transition(
      id,
      time,
      optional(scene_time, fn(value) { value.cast() }),
    ),
    playback.source,
  )
}
