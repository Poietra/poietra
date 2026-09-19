///|
pub fn property_channel_name(channel : @scene.PropertyChannel) -> String {
  match channel {
    Position => "position"
    Opacity => "opacity"
    Size => "size"
    Rotation => "rotation"
    Fill => "fill"
    Stroke => "stroke"
    StrokeWidth => "strokeWidth"
    FontSize => "fontSize"
    CornerRadius => "cornerRadius"
    ShapePath => "path"
    Reveal => "reveal"
  }
}

///|
pub fn property_channel_label(channel : @scene.PropertyChannel) -> String {
  match channel {
    Position => "Position"
    Opacity => "Opacity"
    Size => "Size"
    Rotation => "Rotation"
    Fill => "Fill"
    Stroke => "Stroke"
    StrokeWidth => "Stroke width"
    FontSize => "Font size"
    CornerRadius => "Corner radius"
    ShapePath => "Shape path"
    Reveal => "Reveal"
  }
}

///|
pub fn property_channels(
  kind : @scene.ObjectKind,
  track : @scene.Track,
) -> Array[@scene.PropertyChannel] {
  [
    @scene.Position,
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
  ].filter(fn(channel) {
    // Imported overrides stay reachable even if the current object no longer uses them.
    if @scene.timing_override(track, channel) is Some(_) {
      return true
    }
    match channel {
      Reveal => track.type_ is Write || track.type_ is Grow
      ShapePath => kind is Path
      FontSize => kind is Text || kind is Equation
      Size => !(kind is Text || kind is Equation)
      CornerRadius => kind is Rectangle || kind is Image || kind is Video
      Fill =>
        !(kind is Image ||
        kind is Video ||
        kind is Path ||
        kind is Arrow ||
        kind is NumberLine)
      _ => true
    }
  })
}

///|
pub(all) enum PropertyTimingChange {
  ResetTiming
  TimingStart(Double)
  TimingDuration(Double)
  TimingEasing(@scene.Easing)
}

///|
pub fn change_property_timing(
  previous : @scene.Timing,
  patch : PropertyTimingChange,
  limit : Double,
) -> @scene.Timing? {
  let next = match patch {
    ResetTiming => return None
    TimingStart(start) => { ..previous, start, }
    TimingDuration(duration) => { ..previous, duration, }
    TimingEasing(easing) => { ..previous, easing, }
  }
  let start = @scene.maximum(0.0, @scene.minimum(next.start, limit))
  Some({
    ..next,
    start,
    duration: @scene.maximum(0.0, @scene.minimum(next.duration, limit - start)),
  })
}
