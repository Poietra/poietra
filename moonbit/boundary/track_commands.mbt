///|
let track_timing_channels : Array[(@scene.PropertyChannel, String)] = @scene.property_channels().map(fn(
    channel,
  ) {
    (channel, @editor.property_channel_name(channel) + "Timing")
  },
)

///|
fn timing_curve(value : @core.Any) -> @scene.Easing? {
  if is_valid_easing(value) {
    Some(@project_codec.decode_Easing(value))
  } else {
    None
  }
}

///|
fn timing_candidate(value : @core.Any) -> @editor.TimingCandidate {
  {
    start: patch_number(value._get("start")),
    duration: patch_number(value._get("duration")),
    easing: timing_curve(value._get("easing")),
  }
}

///|
pub fn single_track_changes(
  scene_id : String,
  transition_id : String,
  object_id : String,
  previous : @core.Any,
  patch : @core.Any,
  limit : Double,
) -> Array[@core.Any] {
  let source = if !truthy(previous) {
    @editor.MissingAnimation
  } else if truthy(previous._get("implicit")) {
    @editor.AutomaticAnimation(timing_curve(previous._get("easing")))
  } else {
    @editor.ExplicitAnimation(timing_candidate(previous))
  }
  let keys = @core.object_keys(patch)
  if keys.length() == 1 && keys[0] == "keyframes" && truthy(previous) {
    return keyframe_changes(
      [
        "scenes", scene_id, "transitions", transition_id, "tracks", object_id, "keyframes",
      ],
      previous._get("keyframes"),
      patch._get("keyframes"),
    )
  }
  let fields = []
  for key in keys {
    match key {
      "start" => fields.push(@editor.SetStart(patch_number(patch._get(key))))
      "duration" =>
        fields.push(@editor.SetDuration(patch_number(patch._get(key))))
      "easing" => fields.push(@editor.SetCurve(timing_curve(patch._get(key))))
      _ => ()
    }
  }
  let property_keys : Set[String] = Set([])
  let properties = []
  for (channel, key) in track_timing_channels {
    let changed = keys.contains(key)
    if changed {
      property_keys.add(key)
    }
    let before = if truthy(previous) {
      previous._get(key)
    } else {
      @core.undefined()
    }
    let after = if changed { patch._get(key) } else { before }
    if truthy(after) || changed {
      properties.push(@editor.PropertyTimingInput::{
        channel,
        previous: if changed && truthy(before) {
          Some(timing_candidate(before))
        } else {
          None
        },
        next: if truthy(after) {
          Some(timing_candidate(after))
        } else {
          None
        },
        changed,
      })
    }
  }
  let plan = match
    @editor.plan_track_command(source, fields, properties, limit) {
    Err(error) => {
      @core.throw_error(animation_timing_error(error))
      return []
    }
    Ok(plan) => plan
  }
  let base = [
    "scenes", scene_id, "transitions", transition_id, "tracks", object_id,
  ]
  if plan.create {
    let value = merge_values(
      @project_codec.encode_Track({
        ..@scene.default_track(object_id, plan.base.duration),
        start: plan.base.start,
        easing: plan.base.easing,
      }),
      patch,
    )
    value._set("implicit", @core.any(false))
    if keys.contains("keyframes") {
      validate_animation_track(value, limit)
    }
    return [make_change(FixedArray::from_array(base[:]), value)]
  }
  let changes = []
  append_timing_fields(changes, base, plan.fields)
  if plan.activate {
    changes.push(
      make_change(
        FixedArray::from_array((base + ["implicit"])[:]),
        if keys.contains("implicit") {
          patch._get("implicit")
        } else {
          @core.any(false)
        },
      ),
    )
  }
  for (channel, update) in plan.properties {
    let key = @editor.property_channel_name(channel) + "Timing"
    changes.append(
      property_timing_changes(base + [key], update, patch._get(key)),
    )
  }
  if keys.contains("keyframes") {
    changes.append(
      keyframe_changes(
        base + ["keyframes"],
        previous._get("keyframes"),
        patch._get("keyframes"),
      ),
    )
  }
  // Non-timing patch values keep their native representation. In particular,
  // explicit null, deletion, path replacement and extension fields are distinct.
  for key in keys {
    if key == "keyframes" ||
      key == "start" ||
      key == "duration" ||
      key == "easing" ||
      property_keys.contains(key) ||
      (key == "implicit" && plan.activate) {
      continue
    }
    changes.push(
      make_change(FixedArray::from_array((base + [key])[:]), patch._get(key)),
    )
  }
  changes
}

///|
/// Keep each existing CRDT keyframe parent and publish changed leaves only.
/// A missing ID in a patch is untouched; deletion is a tombstone on that ID.
pub fn keyframe_changes(
  base : Array[String],
  previous : @core.Any,
  patch : @core.Any,
) -> Array[@core.Any] {
  if @core.is_nullish(previous) {
    @core.throw_error(
      "キーフレームの初期同期が完了していません。",
    )
  }
  if @core.is_nullish(patch) ||
    @core.typeof_(patch) != "object" ||
    @core.is_array(patch) {
    @core.throw_error(
      "キーフレームは ID ごとの編集値で指定してください。",
    )
  }
  let ids : Set[String] = Set([])
  for id in @core.object_keys(previous) {
    ids.add(id)
  }
  let changes = []
  for id in @core.object_keys(patch) {
    if !valid_document_id(id) {
      @core.throw_error("キーフレーム ID が無効です。")
    }
    ids.add(id)
    let old = previous._get(id)
    let next = if truthy(old) {
      merge_values(old, patch._get(id))
    } else {
      patch._get(id)
    }
    validate_keyframe(next)
    if !truthy(old) {
      changes.push(
        make_change(
          FixedArray::from_array((base + [id])[:]),
          write_keyframe(read_keyframe(next)),
        ),
      )
    } else {
      for key in @core.object_keys(patch._get(id)) {
        if ["at", "value", "easing", "property", "deleted"].contains(key) &&
          !same_value(old._get(key), next._get(key)) {
          changes.push(
            make_change(
              FixedArray::from_array((base + [id, key])[:]),
              next._get(key),
            ),
          )
        }
      }
    }
  }
  if ids.length() > 1024 {
    @core.throw_error("キーフレームが 1024 個を超えています。")
  }
  changes
}
