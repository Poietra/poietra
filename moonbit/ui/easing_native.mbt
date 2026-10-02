///|
/// Public JS props are decoded here; internal callers retain Easing and typed
/// callbacks all the way through rendering and pointer gestures.
pub fn easing_editor(input : @core.Any) -> @react.Element {
  render_easing_editor({
    value: read_optional_easing(input._get("value")),
    label: input._get("label").cast(),
    disabled: truthy(input._get("disabled")),
    disabled_reason: if truthy(input._get("disabledReason")) {
      Some(input._get("disabledReason").cast())
    } else {
      None
    },
    current: if truthy(input._get("getValue")) {
      Some(fn() { read_optional_easing(input._get("getValue")._invoke([])) })
    } else {
      None
    },
    on_change: fn(value, separate) {
      let args : FixedArray[@core.Any] = if separate {
        [@boundary.write_easing(value)]
      } else {
        [@boundary.write_easing(value), @core.any(false)]
      }
      input._get("onChange")._invoke(args) |> ignore
    },
  })
}

///|
fn read_optional_easing(value : @core.Any) -> @scene.Easing? {
  if @core.is_nullish(value) {
    None
  } else {
    Some(@boundary.read_easing(value))
  }
}

///|
fn native_group_easing(
  store : @core.Any,
  scene_id : String,
  transition_id : String,
  ids : FixedArray[String],
) -> @scene.Easing? {
  let current = store._call("project", [])._get("scenes")._get(scene_id)
  if !truthy(current) {
    return None
  }
  read_optional_easing(
    @boundary.common_track_value(
      @boundary.group_animation_targets(current, transition_id, ids)
      ._get("targets")
      .cast(),
      "easing",
    ),
  )
}
