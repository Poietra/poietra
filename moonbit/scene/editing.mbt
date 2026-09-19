///|
pub(all) enum PropertyChannel {
  Position
  Opacity
  Size
  Rotation
  Fill
  Stroke
  StrokeWidth
  FontSize
  CornerRadius
  ShapePath
  Reveal
} derive(Eq)

///|
pub fn property_channel(value : String) -> PropertyChannel? {
  match value {
    "position" => Some(Position)
    "opacity" => Some(Opacity)
    "size" => Some(Size)
    "rotation" => Some(Rotation)
    "fill" => Some(Fill)
    "stroke" => Some(Stroke)
    "strokeWidth" => Some(StrokeWidth)
    "fontSize" => Some(FontSize)
    "cornerRadius" => Some(CornerRadius)
    "path" => Some(ShapePath)
    "reveal" => Some(Reveal)
    _ => None
  }
}

///|
pub fn timing_override(track : Track, channel : PropertyChannel) -> Timing? {
  match channel {
    Position => track.positionTiming
    Opacity => track.opacityTiming
    Size => track.sizeTiming
    Rotation => track.rotationTiming
    Fill => track.fillTiming
    Stroke => track.strokeTiming
    StrokeWidth => track.strokeWidthTiming
    FontSize => track.fontSizeTiming
    CornerRadius => track.cornerRadiusTiming
    ShapePath => track.pathTiming
    Reveal => track.revealTiming
  }
}

///|
pub fn track_timing_end(track : Track, include_base : Bool) -> Double {
  let mut end = if include_base { track.start + track.duration } else { 0.0 }
  for
    timing in [
      track.positionTiming,
      track.opacityTiming,
      track.sizeTiming,
      track.rotationTiming,
      track.fillTiming,
      track.strokeTiming,
      track.strokeWidthTiming,
      track.fontSizeTiming,
      track.cornerRadiusTiming,
      track.pathTiming,
      track.revealTiming,
    ] {
    if timing is Some(value) {
      end = maximum(end, value.start + value.duration)
    }
  }
  end
}

///|
pub fn valid_easing(value : Easing) -> Bool {
  match value {
    CubicBezier(x1, y1, x2, y2) =>
      [x1, y1, x2, y2].all(fn(v) {
        !v.is_nan() && !v.is_inf() && v >= 0.0 && v <= 1.0
      })
    _ => true
  }
}

///|
pub fn valid_timing_bounds(
  start : Double,
  duration : Double,
  limit : Double,
) -> Bool {
  !start.is_nan() &&
  !duration.is_nan() &&
  !start.is_inf() &&
  !duration.is_inf() &&
  start >= 0.0 &&
  duration >= 0.0 &&
  !(start + duration > limit)
}

///|
pub fn default_state(kind : ObjectKind) -> ObjectState {
  let line = kind == Path || kind == Arrow || kind == NumberLine
  {
    x: 640.0,
    y: 360.0,
    width: if line {
      400.0
    } else {
      100.0
    },
    height: if kind == Path {
      -180.0
    } else if line {
      0.0
    } else {
      100.0
    },
    rotation: 0.0,
    opacity: 1.0,
    visible: true,
    fill: "#d7d8e4",
    stroke: "#67c4d9",
    strokeWidth: if line {
      2.0
    } else {
      0.0
    },
    text: if kind == Equation {
      "y = \\sigma(x)"
    } else {
      "Your idea, in motion."
    },
    fontSize: if kind == Equation {
      42.0
    } else {
      36.0
    },
    cornerRadius: 8.0,
    effect: Normal,
    path: { c1: { x: 140.0, y: 0.0, }, c2: { x: 260.0, y: -180.0, }, },
  }
}
