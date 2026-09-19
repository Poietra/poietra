///|
pub fn animation_timing_error(error : @editor.AnimationTimingError) -> String {
  match error {
    TransitionBounds =>
      "Transition の長さは 0〜120000 ms にしてください。"
    TimingBounds =>
      "アニメーションの開始時刻と長さが Transition の範囲を超えています。"
    EasingBounds =>
      "イージングの形式が無効です。ベジェ曲線の制御点は 0〜1 で指定してください。"
  }
}

///|
fn append_timing_fields(
  changes : Array[@core.Any],
  path : Array[String],
  fields : Array[@editor.TimingField],
) -> Unit {
  for field in fields {
    let (key, value) = match field {
      StartTime(value) => ("start", @core.any(value))
      DurationTime(value) => ("duration", @core.any(value))
      EasingCurve(value) => ("easing", encode_Easing(value))
    }
    let path = path + [key]
    changes.push(make_change(FixedArray::from_array(path[:]), value))
  }
}

///|
pub fn transition_resize_changes(
  scene_id : String,
  transition_id : String,
  plan : @editor.TransitionResize,
) -> Array[@core.Any] {
  let base = ["scenes", scene_id, "transitions", transition_id]
  let changes = [
    make_change(
      ["scenes", scene_id, "transitions", transition_id, "duration"],
      @core.any(plan.duration),
    ),
  ]
  for track in plan.tracks {
    let path = base + ["tracks", track.object_id]
    if track.channel is Some(channel) {
      path.push(@editor.property_channel_name(channel) + "Timing")
    }
    append_timing_fields(changes, path, track.fields)
  }
  changes
}

///|
pub fn property_timing_changes(
  path : Array[String],
  plan : @editor.TimingUpdate,
  cleared : @core.Any,
) -> Array[@core.Any] {
  match plan {
    KeepTiming => []
    ClearTiming => [make_change(FixedArray::from_array(path[:]), cleared)]
    NewTiming(timing) =>
      [make_change(FixedArray::from_array(path[:]), encode_Timing(timing))]
    TimingFields(fields) => {
      let changes = []
      append_timing_fields(changes, path, fields)
      changes
    }
  }
}
