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
    Some(decode_Easing(value))
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
      encode_Track({
        ..@scene.default_track(object_id, plan.base.duration),
        start: plan.base.start,
        easing: plan.base.easing,
      }),
      patch,
    )
    value._set("implicit", @core.any(false))
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
  // Non-timing patch values keep their native representation. In particular,
  // explicit null, deletion, path replacement and extension fields are distinct.
  for key in keys {
    if key == "start" ||
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
