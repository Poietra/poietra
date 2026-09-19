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
    let result = make_render_object(
      input._get("objects")._get(item.object.id),
      encode_ObjectState(item.state),
      item.writeProgress,
      item.order,
      @core.from_option(item.videoTimeMs),
    )
    if item.world is Some(world) {
      put_own(result, "world", encode_Affine(world))
    }
    result
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
  let composition = decode_Composition(value)
  let time : Double = if @core.is_undefined(time) {
    @scene.timeline_segments(decode_timeline(input))
    .iter()
    .find_first(fn(segment) {
      segment.kind == "composition" && segment.id == composition.id
    })
    .map(fn(segment) { segment.start })
    .unwrap_or(0.0)
  } else {
    time.cast()
  }
  frame_value(
    {
      objects: @scene.composition_objects(
        ordered_objects(input).iter().map(decode_SceneObject).to_array(),
        composition,
        time,
      ),
      background: input._get("background").cast(),
      width: input._get("width").cast(),
      height: input._get("height").cast(),
    },
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
  let segments = @scene.timeline_segments(decode_timeline(input))
  @core.any(
    FixedArray::makei(segments.length(), fn(i) {
      let segment = segments[i]
      make_segment(segment.kind, segment.id, segment.start, segment.duration)
    }),
  )
}

///|
extern "js" fn make_segment(
  kind : String,
  id : String,
  start : Double,
  duration : Double,
) -> @core.Any =
  #|(kind, id, start, duration) => ({kind, id, start, duration})

///|
pub fn scene_duration(input : @core.Any) -> Double {
  @scene.timeline_duration(decode_timeline(input))
}

///|
pub fn track_progress(
  host : @core.Any,
  time : Double,
  start : Double,
  duration : Double,
  easing : @core.Any,
) -> Double {
  @scene.timing_progress(
    { start, duration, easing: decode_Easing(easing), },
    time,
    kernel(host),
  )
}

///|
pub fn read_kernel(value : @core.Any) -> @scene.Kernel {
  kernel(value)
}
