///|
pub fn model_catalog() -> @core.Any {
  let kinds = @core.new_object()
  for kind in @scene.object_kinds {
    kinds._set(
      @scene.object_kind_name(kind),
      @core.any(@scene.object_kind_label(kind)),
    )
  }
  let animations = @core.new_object()
  for kind in @scene.animations {
    animations._set(
      @scene.animation_name(kind),
      @core.any(@scene.animation_label(kind)),
    )
  }
  let channels : Array[@scene.PropertyChannel] = [
    Position,
    Opacity,
    Size,
    Rotation,
    Fill,
    Stroke,
    StrokeWidth,
    FontSize,
    CornerRadius,
    ShapePath,
    Reveal,
  ]
  let labels = @core.new_object()
  for channel in channels {
    labels._set(
      @editor.property_channel_name(channel),
      @core.any(@editor.property_channel_label(channel)),
    )
  }
  @core.from_entries([
    ("colors", @core.any(FixedArray::from_array(@scene.colors[:]))),
    ("kinds", kinds),
    ("animations", animations),
    (
      "channels",
      @core.any(
        FixedArray::from_array(channels.map(@editor.property_channel_name)[:]),
      ),
    ),
    ("labels", labels),
    (
      "easings",
      @core.from_entries([
        ("linear", @core.any("Linear")),
        ("easeInOut", @core.any("Ease in out")),
        ("easeIn", @core.any("Ease in")),
        ("easeOut", @core.any("Ease out")),
      ]),
    ),
  ])
}

///|
pub fn default_custom_easing() -> @core.Any {
  @core.global_this()
  ._get("Object")
  ._call("freeze", [
    @project_codec.encode_Easing(@scene.CubicBezier(0.25, 0.1, 0.25, 1.0)),
  ])
}

///|
pub fn new_id_default(prefix : @core.Any) -> String {
  new_id(if @core.is_undefined(prefix) { "obj" } else { prefix.cast() })
}

///|
pub fn track_timing_end_default(
  track : @core.Any,
  include_base : @core.Any,
) -> Double {
  track_timing_end(
    track,
    if @core.is_undefined(include_base) {
      true
    } else {
      include_base.cast()
    },
  )
}
