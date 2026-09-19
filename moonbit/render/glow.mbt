///|
pub(all) struct GraphicsLimits {
  texture : Int
  viewport_width : Int
  viewport_height : Int
}

///|
pub(all) enum GlowPass {
  Horizontal
  Vertical
  Composite(Bool)
} derive(Eq, Debug)

///|
pub(all) enum GlowProblem {
  InvalidExtent
  InvalidRadius
} derive(Eq, Debug)

///|
pub(all) struct GlowPlan {
  width : Int
  height : Int
  sigma : Double
  radius : Int
  passes : Array[GlowPass]
}

///|
/// The render program and device limits are plain data; only the browser driver
/// owns native GPU resources. This follows the separation explored in mizchi/gfx.
pub fn glow_plan(
  width : Double,
  height : Double,
  sigma : Double,
  limits : GraphicsLimits,
) -> Result[GlowPlan, GlowProblem] {
  if width.is_nan() ||
    height.is_nan() ||
    width.is_inf() ||
    height.is_inf() ||
    width <= 0.0 ||
    height <= 0.0 ||
    width.trunc() != width ||
    height.trunc() != height ||
    width > limits.texture.to_double() ||
    height > limits.texture.to_double() ||
    width > limits.viewport_width.to_double() ||
    height > limits.viewport_height.to_double() {
    return Err(InvalidExtent)
  }
  let radius = (sigma * 4.0).ceil()
  if sigma.is_nan() ||
    sigma.is_inf() ||
    sigma < 0.0 ||
    radius > limits.texture.to_double() {
    return Err(InvalidRadius)
  }
  Ok({
    width: width.to_int(),
    height: height.to_int(),
    sigma,
    radius: radius.to_int(),
    passes: if sigma > 0.0 {
      [Horizontal, Vertical, Composite(true)]
    } else {
      [Composite(false)]
    },
  })
}
