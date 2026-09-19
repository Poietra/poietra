///|
extern "js" fn merge_values(base : @core.Any, patch : @core.Any) -> @core.Any =
  #|(base, patch) => ({...base, ...patch})

///|
extern "js" fn strict_equal(a : @core.Any, b : @core.Any) -> Bool =
  #|(a, b) => a === b

///|
pub fn read_easing(value : @core.Any) -> @scene.Easing {
  decode_Easing(value)
}

///|
pub fn write_easing(value : @scene.Easing) -> @core.Any {
  encode_Easing(value)
}

///|
pub fn read_track(value : @core.Any) -> @scene.Track {
  decode_Track(value)
}

///|
pub fn read_timing(value : @core.Any) -> @scene.Timing {
  decode_Timing(value)
}

///|
pub fn write_timing(value : @scene.Timing) -> @core.Any {
  encode_Timing(value)
}

///|
pub fn read_object_kind(value : @core.Any) -> @scene.ObjectKind {
  decode_ObjectKind(value)
}

///|
pub fn is_valid_easing(value : @core.Any) -> Bool {
  if @core.typeof_(value) == "string" {
    let name : String = value.cast()
    return name == "linear" ||
      name == "easeInOut" ||
      name == "easeIn" ||
      name == "easeOut"
  }
  if @core.is_nullish(value) ||
    @core.typeof_(value) != "object" ||
    is_array(value) {
    return false
  }
  let keys = @core.object_keys(value)
  if keys.length() != 5 {
    return false
  }
  for key in keys {
    if key != "type" && key != "x1" && key != "y1" && key != "x2" && key != "y2" {
      return false
    }
  }
  if !strict_equal(value._get("type"), @core.any("cubicBezier")) {
    return false
  }
  for key in ["x1", "y1", "x2", "y2"] {
    if @core.typeof_(value._get(key)) != "number" {
      return false
    }
  }
  @scene.valid_easing(decode_Easing(value))
}

///|
pub fn easings_equal(a : @core.Any, b : @core.Any) -> Bool {
  if strict_equal(a, b) {
    return true
  }
  if !truthy(a) ||
    !truthy(b) ||
    @core.typeof_(a) != "object" ||
    @core.typeof_(b) != "object" {
    return false
  }
  for key in ["type", "x1", "y1", "x2", "y2"] {
    if !strict_equal(a._get(key), b._get(key)) {
      return false
    }
  }
  true
}

///|
pub fn default_state(kind : @core.Any, overrides : @core.Any) -> @core.Any {
  merge_values(
    encode_ObjectState(@scene.default_state(decode_ObjectKind(kind))),
    overrides,
  )
}

///|
fn track_value(track : @scene.Track) -> @core.Any {
  encode_Track(track)
}

///|
pub fn default_track(object_id : String, overrides : @core.Any) -> @core.Any {
  merge_values(track_value(@scene.default_track(object_id, 800.0)), overrides)
}

///|
pub fn resolve_track(
  input : @core.Any,
  object_id : String,
  duration : Double,
) -> @core.Any {
  if !truthy(input) {
    return track_value(@scene.default_track(object_id, duration))
  }
  if !truthy(input._get("implicit")) {
    return input
  }
  let resolved = @scene.resolve_track(
    Some(decode_Track(input)),
    object_id,
    duration,
  )
  merge_values(input, timing_fields(resolved.start, resolved.duration))
}

///|
extern "js" fn timing_fields(start : Double, duration : Double) -> @core.Any =
  #|(start, duration) => ({start, duration})

///|
pub fn implicit_tracks(
  ids : FixedArray[String],
  duration : Double,
) -> @core.Any {
  let result = @core.new_object()
  for id in ids {
    let track = @scene.default_track(id, duration)
    put_own(result, id, track_value({ ..track, implicit: Some(true), }))
  }
  result
}

///|
pub fn property_timing_key(channel : String) -> String {
  channel + "Timing"
}

///|
pub fn get_property_timing(track : @core.Any, channel : String) -> @core.Any {
  let value = track._get(property_timing_key(channel))
  if !@core.is_nullish(value) {
    return value
  }
  make_timing(track._get("start"), track._get("duration"), track._get("easing"))
}

///|
extern "js" fn make_timing(
  start : @core.Any,
  duration : @core.Any,
  easing : @core.Any,
) -> @core.Any =
  #|(start, duration, easing) => ({start, duration, easing})

///|
pub fn has_property_timing(track : @core.Any, channel : String) -> Bool {
  !@core.is_nullish(track._get(property_timing_key(channel)))
}

///|
pub fn track_timing_end(track : @core.Any, include_base : Bool) -> Double {
  @scene.track_timing_end(decode_Track(track), include_base)
}

///|
pub fn validate_animation_timing(timing : @core.Any, limit : Double) -> Unit {
  let start = timing._get("start")
  let duration = timing._get("duration")
  if @core.typeof_(start) != "number" ||
    @core.typeof_(duration) != "number" ||
    !@scene.valid_timing_bounds(start.cast(), duration.cast(), limit) {
    @core.throw_error(
      "アニメーションの開始時刻と長さが Transition の範囲を超えています。",
    )
  }
  if !is_valid_easing(timing._get("easing")) {
    @core.throw_error(
      "イージングの形式が無効です。ベジェ曲線の制御点は 0〜1 で指定してください。",
    )
  }
}

///|
pub fn validate_animation_track(track : @core.Any, duration : Double) -> Unit {
  // Keep validation at the untrusted representation boundary: unknown easing
  // names must not enter the typed evaluator as a silent default.
  let resolved = if truthy(track._get("implicit")) {
    merge_values(track, timing_fields(0.0, duration))
  } else {
    track
  }
  validate_animation_timing(resolved, duration)
  for
    channel in [
      "position", "opacity", "size", "rotation", "fill", "stroke", "strokeWidth",
      "fontSize", "cornerRadius", "path", "reveal",
    ] {
    let timing = track._get(property_timing_key(channel))
    if truthy(timing) {
      validate_animation_timing(timing, duration)
    }
  }
}

///|
pub fn clamp(value : Double, low : Double, high : Double) -> Double {
  @scene.clamp(value, low, high)
}

///|
pub fn state_for(
  scene : @core.Any,
  composition_id : String,
  object_id : String,
) -> @core.Any {
  let composition = scene._get("compositions")._get(composition_id)
  if @core.is_nullish(composition) {
    @core.undefined()
  } else {
    composition._get("states")._get(object_id)
  }
}

///|
pub fn ordered_objects(scene : @core.Any) -> FixedArray[@core.Any] {
  let objects = scene._get("objects")
  let ids = @core.object_keys(objects)
  ids.sort_by(fn(a, b) {
    let first : Double = objects._get(a)._get("order").cast()
    let second : Double = objects._get(b)._get("order").cast()
    let delta = first - second
    if delta.is_nan() || delta == 0.0 {
      compare_ids(
        objects._get(a)._get("id").cast(),
        objects._get(b)._get("id").cast(),
      )
    } else if delta < 0.0 {
      -1
    } else {
      1
    }
  })
  FixedArray::makei(ids.length(), fn(i) { objects._get(ids[i]) })
}

///|
extern "js" fn host_new_id(prefix : String) -> String =
  #|prefix => `${prefix}_${crypto.randomUUID().replaceAll('-', '').slice(0, 16)}`

///|
extern "js" fn host_format_milliseconds(value : Double) -> String =
  #|value => Math.round(value).toLocaleString('en-US')

///|
pub fn new_id(prefix : String) -> String {
  host_new_id(prefix)
}

///|
pub fn format_milliseconds(value : Double) -> String {
  host_format_milliseconds(value)
}
