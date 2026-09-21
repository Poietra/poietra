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
  {
    program: @scene.prepare_scene(
      @project_codec.decode_Scene(source),
      kernel(host),
    ),
    source,
  }
}

///|
pub fn playback_frame(playback : Playback, time : Double) -> @core.Any {
  frame_value(playback.program.evaluate(time), playback.source)
}

///|
pub fn playback_static_key(playback : Playback, time : Double) -> Int? {
  playback.program.static_frame_key(time)
}

///|
pub fn compile_scene(input : @core.Any, host : @core.Any) -> @core.Any {
  let playback = prepare_playback(input, host)
  @core.from_entries([
    (
      "evaluate",
      @core.any(fn(time : Double) { playback_frame(playback, time) }),
    ),
    (
      "composition",
      @core.any(fn(id : String, time : @core.Any) {
        playback_composition(playback, id, time)
      }),
    ),
    (
      "transition",
      @core.any(fn(id : String, time : Double, scene_time : @core.Any) {
        playback_transition(playback, id, time, scene_time)
      }),
    ),
  ])
}

///|
pub fn playback_composition(
  playback : Playback,
  id : String,
  time : @core.Any,
) -> @core.Any {
  frame_value(
    playback.program.composition(
      id,
      @project_codec.optional(time, fn(value) { value.cast() }),
    ),
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
      @project_codec.optional(scene_time, fn(value) { value.cast() }),
    ),
    playback.source,
  )
}
