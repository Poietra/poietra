///|
fn[T : ToJson] encode(value : T) -> @core.Any {
  @core.json_parse(value.to_json().stringify())
}

///|
extern "js" fn compare_ids(a : String, b : String) -> Int =
  #|(a, b) => a.localeCompare(b)

///|
fn kernel(value : @core.Any) -> @scene.Kernel {
  {
    track_progress: value._get("track_progress").cast(),
    interpolate: value._get("interpolate").cast(),
    cubic_bezier: value._get("cubic_bezier").cast(),
    cubic_bezier_ease: value._get("cubic_bezier_ease").cast(),
    compare_ids,
  }
}

///|
/// Preserve the public object reference, including optional metadata and nulls.
fn frame_value(frame : @scene.Frame, input : @core.Any) -> @core.Any {
  let objects = FixedArray::makei(frame.objects.length(), fn(i) {
    let item = frame.objects[i]
    make_render_object(
      input._get("objects")._get(item.object.id),
      encode_ObjectState(item.state),
      item.writeProgress,
      item.order,
      @core.from_option(item.videoTimeMs),
    )
  })
  make_frame(objects, frame.background, frame.width, frame.height)
}

///|
extern "js" fn make_render_object(
  object : @core.Any,
  state : @core.Any,
  write : Double,
  order : String,
  video : @core.Any,
) -> @core.Any =
  #|(object, state, writeProgress, order, videoTimeMs) => videoTimeMs == null ? {object, state, writeProgress, order} : {object, state, writeProgress, order, videoTimeMs}

///|
extern "js" fn make_frame(
  objects : FixedArray[@core.Any],
  background : String,
  width : Double,
  height : Double,
) -> @core.Any =
  #|(objects, background, width, height) => ({objects, background, width, height})

///|
pub fn evaluate_scene(
  input : @core.Any,
  time : Double,
  host : @core.Any,
) -> @core.Any {
  frame_value(
    @scene.evaluate_scene(decode_Scene(input), time, kernel(host)),
    input,
  )
}

///|
pub fn composition_frame(
  input : @core.Any,
  value : @core.Any,
  time : @core.Any,
) -> @core.Any {
  let scene = decode_Scene(input)
  let composition = decode_Composition(value)
  let time : Double = if @core.is_undefined(time) {
    @scene.segment_start(scene, "composition", composition.id)
  } else {
    time.cast()
  }
  frame_value(
    @scene.composition_frame(scene, composition, time, compare_ids),
    input,
  )
}

///|
pub fn transition_frame(
  input : @core.Any,
  value : @core.Any,
  time : Double,
  host : @core.Any,
  scene_time : @core.Any,
) -> @core.Any {
  let scene = decode_Scene(input)
  let transition = decode_Transition(value)
  let scene_time : Double = if @core.is_undefined(scene_time) {
    @scene.segment_start(scene, "transition", transition.id) + time
  } else {
    scene_time.cast()
  }
  frame_value(
    @scene.transition_frame(scene, transition, time, scene_time, kernel(host)),
    input,
  )
}

///|
pub fn scene_segments(input : @core.Any) -> @core.Any {
  encode(@scene.scene_segments(decode_Scene(input)))
}

///|
pub fn scene_duration(input : @core.Any) -> Double {
  @scene.scene_duration(decode_Scene(input))
}
