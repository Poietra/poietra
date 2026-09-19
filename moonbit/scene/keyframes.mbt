///|
/// Intermediate values; endpoints always come from the two Compositions.
/// A key's easing applies to the segment leaving that key. The first segment
/// inherits the selected property's easing. Time is relative to its timing span.
pub fn curve_channel(property : CurveProperty) -> PropertyChannel {
  match property {
    PositionX => Position
    PositionY => Position
    ObjectWidth => Size
    ObjectHeight => Size
    ObjectRotation => Rotation
    ObjectOpacity => Opacity
    ObjectFill => Fill
    ObjectStroke => Stroke
    ObjectStrokeWidth => StrokeWidth
    ObjectFontSize => FontSize
    ObjectCornerRadius => CornerRadius
    Control1X => ShapePath
    Control1Y => ShapePath
    Control2X => ShapePath
    Control2Y => ShapePath
    ObjectReveal => Reveal
    ObjectAnchorX => Position
    ObjectAnchorY => Position
    ObjectScaleX => Size
    ObjectScaleY => Size
    ObjectShear => Rotation
  }
}

///|
pub fn curve_properties(channel : PropertyChannel) -> Array[CurveProperty] {
  [
    PositionX,
    PositionY,
    ObjectWidth,
    ObjectHeight,
    ObjectRotation,
    ObjectOpacity,
    ObjectFill,
    ObjectStroke,
    ObjectStrokeWidth,
    ObjectFontSize,
    ObjectCornerRadius,
    Control1X,
    Control1Y,
    Control2X,
    Control2Y,
    ObjectReveal,
    ObjectAnchorX,
    ObjectAnchorY,
    ObjectScaleX,
    ObjectScaleY,
    ObjectShear,
  ].filter(fn(p) { curve_channel(p) == channel })
}

///|
pub fn state_curve_value(
  state : ObjectState,
  property : CurveProperty,
) -> CurveValue {
  match property {
    PositionX => CurveNumber(state.x)
    PositionY => CurveNumber(state.y)
    ObjectWidth => CurveNumber(state.width)
    ObjectHeight => CurveNumber(state.height)
    ObjectRotation => CurveNumber(state.rotation)
    ObjectOpacity => CurveNumber(state.opacity)
    ObjectFill => CurveColor(state.fill)
    ObjectStroke => CurveColor(state.stroke)
    ObjectStrokeWidth => CurveNumber(state.strokeWidth)
    ObjectFontSize => CurveNumber(state.fontSize)
    ObjectCornerRadius => CurveNumber(state.cornerRadius)
    Control1X => CurveNumber(state.path.c1.x)
    Control1Y => CurveNumber(state.path.c1.y)
    Control2X => CurveNumber(state.path.c2.x)
    Control2Y => CurveNumber(state.path.c2.y)
    ObjectReveal => CurveNumber(1.0)
    ObjectAnchorX => CurveNumber(state.anchorX.unwrap_or(0.0))
    ObjectAnchorY => CurveNumber(state.anchorY.unwrap_or(0.0))
    ObjectScaleX => CurveNumber(state.scaleX.unwrap_or(1.0))
    ObjectScaleY => CurveNumber(state.scaleY.unwrap_or(1.0))
    ObjectShear => CurveNumber(state.shear.unwrap_or(0.0))
  }
}

///|
pub fn with_curve_value(
  state : ObjectState,
  property : CurveProperty,
  value : CurveValue,
) -> ObjectState {
  match (property, value) {
    (PositionX, CurveNumber(value)) => { ..state, x: value, }
    (PositionY, CurveNumber(value)) => { ..state, y: value, }
    (ObjectWidth, CurveNumber(value)) => { ..state, width: value, }
    (ObjectHeight, CurveNumber(value)) => { ..state, height: value, }
    (ObjectRotation, CurveNumber(value)) => { ..state, rotation: value, }
    (ObjectOpacity, CurveNumber(value)) => { ..state, opacity: value, }
    (ObjectFill, CurveColor(value)) => { ..state, fill: value, }
    (ObjectStroke, CurveColor(value)) => { ..state, stroke: value, }
    (ObjectStrokeWidth, CurveNumber(value)) => { ..state, strokeWidth: value, }
    (ObjectFontSize, CurveNumber(value)) => { ..state, fontSize: value, }
    (ObjectCornerRadius, CurveNumber(value)) =>
      { ..state, cornerRadius: value, }
    (Control1X, CurveNumber(value)) =>
      { ..state, path: { ..state.path, c1: { ..state.path.c1, x: value, }, }, }
    (Control1Y, CurveNumber(value)) =>
      { ..state, path: { ..state.path, c1: { ..state.path.c1, y: value, }, }, }
    (Control2X, CurveNumber(value)) =>
      { ..state, path: { ..state.path, c2: { ..state.path.c2, x: value, }, }, }
    (Control2Y, CurveNumber(value)) =>
      { ..state, path: { ..state.path, c2: { ..state.path.c2, y: value, }, }, }
    (ObjectAnchorX, CurveNumber(value)) => { ..state, anchorX: Some(value), }
    (ObjectAnchorY, CurveNumber(value)) => { ..state, anchorY: Some(value), }
    (ObjectScaleX, CurveNumber(value)) => { ..state, scaleX: Some(value), }
    (ObjectScaleY, CurveNumber(value)) => { ..state, scaleY: Some(value), }
    (ObjectShear, CurveNumber(value)) => { ..state, shear: Some(value), }
    _ => state
  }
}

///|
pub fn valid_keyframe(key : Keyframe) -> Bool {
  if key.at.is_nan() ||
    key.at <= 0.0 ||
    key.at >= 1.0 ||
    !valid_easing(key.easing) {
    return false
  }
  match (key.property, key.value) {
    (ObjectFill | ObjectStroke, CurveColor(value)) =>
      parse_rgb(value) is Some(_)
    (ObjectFill | ObjectStroke, _) => false
    (_, CurveNumber(value)) => {
      if value.is_nan() || value.is_inf() || value.abs() > 100000.0 {
        return false
      }
      match key.property {
        ObjectOpacity | ObjectReveal => value >= 0.0 && value <= 1.0
        ObjectStrokeWidth | ObjectFontSize | ObjectCornerRadius =>
          value >= 0.0 && value <= 10000.0
        _ => true
      }
    }
    _ => false
  }
}

///|
priv enum CurveSegmentValue {
  Numbers(Double, Double)
  Colors(ColorProgram)
}

///|
priv struct ValueSegment {
  end : Double
  timing : Timing
  value : CurveSegmentValue
}

///|
pub struct PreparedCurve {
  property : CurveProperty
  priv timing : Timing
  priv segments : Array[ValueSegment]
}

///|
fn value_segment(a : CurveValue, b : CurveValue) -> CurveSegmentValue {
  match (a, b) {
    (CurveNumber(a), CurveNumber(b)) => Numbers(a, b)
    (CurveColor(a), CurveColor(b)) => Colors(prepare_color(a, b))
    _ => Numbers(0.0, 0.0)
  }
}

///|
/// Stable IDs allow independent CRDT insertion/removal. Equal-time keys retain
/// their data; the lexically greatest ID wins evaluation on every replica.
pub fn prepare_curve(
  track : Track,
  property : CurveProperty,
  from : CurveValue,
  to : CurveValue,
) -> PreparedCurve? {
  guard track.keyframes is Some(keys) else { return None }
  let points : Array[(String, Keyframe)] = []
  for id, key in keys {
    if key.property == property &&
      key.deleted != Some(true) &&
      valid_keyframe(key) {
      points.push((id, key))
    }
  }
  if points.is_empty() {
    return None
  }
  points.sort_by(fn(a, b) {
    if a.1.at < b.1.at {
      -1
    } else if a.1.at > b.1.at {
      1
    } else {
      a.0.compare(b.0)
    }
  })
  let unique : Array[Keyframe] = []
  for (_, key) in points {
    if unique.last() is Some(last) && last.at == key.at {
      unique[unique.length() - 1] = key
    } else {
      unique.push(key)
    }
  }
  let timing = timing_override(track, curve_channel(property)).unwrap_or({
    start: track.start,
    duration: track.duration,
    easing: track.easing,
  })
  let segments : Array[ValueSegment] = []
  let mut previous = from
  let mut start = 0.0
  let mut easing = timing.easing
  for key in unique {
    segments.push({
      end: key.at,
      timing: { start, duration: key.at - start, easing, },
      value: value_segment(previous, key.value),
    })
    previous = key.value
    start = key.at
    easing = key.easing
  }
  segments.push({
    end: 1.0,
    timing: { start, duration: 1.0 - start, easing, },
    value: value_segment(previous, to),
  })
  Some({ property, timing, segments, })
}

///|
/// O(log keyframes) seeks. Sorting and colour parsing occur only at preparation.
pub fn PreparedCurve::evaluate(
  self : PreparedCurve,
  time : Double,
  kernel : Kernel,
) -> CurveValue {
  let at = if time < self.timing.start {
    0.0
  } else if self.timing.duration <= 0.0 {
    1.0
  } else {
    clamp((time - self.timing.start) / self.timing.duration, 0.0, 1.0)
  }
  let mut low = 0
  let mut high = self.segments.length() - 1
  while low < high {
    let middle = low + (high - low) / 2
    if at < self.segments[middle].end {
      high = middle
    } else {
      low = middle + 1
    }
  }
  let segment = self.segments[low]
  let progress = timing_progress(segment.timing, at, kernel)
  match segment.value {
    Numbers(a, b) => CurveNumber((kernel.interpolate)(a, b, progress))
    Colors(value) => CurveColor(color(value, progress))
  }
}

///|
pub fn prepare_object_curves(
  track : Track,
  a : ObjectState,
  b : ObjectState,
  a_visible : Bool,
  b_visible : Bool,
) -> Array[PreparedCurve] {
  let curves : Array[PreparedCurve] = []
  guard track.type_ != Cut && track.keyframes is Some(keys) && !keys.is_empty() else {
    return curves
  }
  for channel in property_channels() {
    for property in curve_properties(channel) {
      let endpoint = fn(state : ObjectState, visible : Bool, from : Bool) {
        if property == ObjectReveal {
          CurveNumber(if from { 0.0 } else { 1.0 })
        } else if !visible &&
          (
            property == ObjectOpacity ||
            (
              track.type_ == Grow &&
              (
                property == ObjectWidth ||
                property == ObjectHeight ||
                property == ObjectFontSize
              )
            )
          ) {
          CurveNumber(0.0)
        } else {
          state_curve_value(state, property)
        }
      }
      if prepare_curve(
          track,
          property,
          endpoint(a, a_visible, true),
          endpoint(b, b_visible, false),
        )
        is Some(curve) {
        curves.push(curve)
      }
    }
  }
  curves
}
