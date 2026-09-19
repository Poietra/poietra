///|
pub let raster_cache_bytes : Double = 33554432.0

///|
pub(all) struct RasterPlan {
  bounds : Bounds
  width : Int
  height : Int
  bytes : Double
}

///|
/// Local appearance is independent of placement, rotation and compositing opacity.
pub fn local_drawable(item : Drawable) -> Drawable {
  {
    ..item,
    world: None,
    state: {
      ..item.state,
      x: 0.0,
      y: 0.0,
      rotation: 0.0,
      anchorX: None,
      anchorY: None,
      scaleX: None,
      scaleY: None,
      shear: None,
      opacity: 1.0,
      visible: true,
      effect: @scene.Normal,
    },
  }
}

///|
pub fn raster_plan(bounds : Bounds, scale : Double, glow : Bool) -> RasterPlan? {
  if scale.is_nan() || scale.is_inf() || scale <= 0.0 {
    return None
  }
  let padding = (if glow { 16.0 } else { 0.0 }) + 1.0 / scale
  let width = @scene.maximum(
    1.0,
    ((bounds.width + padding * 2.0) * scale).ceil(),
  )
  let height = @scene.maximum(
    1.0,
    ((bounds.height + padding * 2.0) * scale).ceil(),
  )
  let bytes = width * height * 4.0
  let x = bounds.x - padding
  let y = bounds.y - padding
  if bytes.is_nan() ||
    bytes.is_inf() ||
    bytes > raster_cache_bytes ||
    x.is_nan() ||
    x.is_inf() ||
    y.is_nan() ||
    y.is_inf() ||
    (width / scale).is_inf() ||
    (height / scale).is_inf() {
    return None
  }
  Some({
    bounds: { x, y, width: width / scale, height: height / scale, },
    width: width.to_int(),
    height: height.to_int(),
    bytes,
  })
}
