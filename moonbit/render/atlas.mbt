///|
pub(all) struct TextAtlasPlan {
  size : Double
  stroke_width : Double
  glyph_count : Int
  metrics : TextMetrics
  x : Double
  y : Double
  width : Int
  height : Int
  columns : Int
  cell_count : Int
  atlas_width : Int
  atlas_height : Int
  scale : Double
  bytes : Double
}

///|
pub fn text_atlas_plan(
  item : Drawable,
  metrics : TextMetrics,
  scale : Double,
  max_bytes : Double,
) -> TextAtlasPlan? {
  if scale.is_nan() || scale.is_inf() || scale <= 0.0 {
    return None
  }
  let size = finite(item.state.fontSize).max(0.0)
  let stroke_width = finite(item.state.strokeWidth).max(0.0)
  let glyph_count = item.state.text.iter().filter(fn(c) { c != '\n' }).count()
  if item.order == Sequential && glyph_count > 128 {
    return None
  }
  let padding = stroke_width / 2.0 + 1.0 / scale
  let raw_width = @scene.maximum(
    1.0,
    ((metrics.width + padding * 2.0) * scale).ceil(),
  )
  let raw_height = @scene.maximum(
    1.0,
    ((metrics.height + padding * 2.0) * scale).ceil(),
  )
  // Validate allocation dimensions before narrowing floating-point values to Int.
  if raw_width.is_nan() ||
    raw_height.is_nan() ||
    raw_width > 4096.0 ||
    raw_height > 4096.0 {
    return None
  }
  let width = raw_width.to_int()
  let height = raw_height.to_int()
  let cell_count = 2 *
    (1 + (if item.order == Sequential { glyph_count } else { 0 }))
  let columns = cell_count.min(4096 / width)
  let rows = (cell_count + columns - 1) / columns
  let atlas_width = columns * width
  let atlas_height = rows * height
  let bytes = (
      atlas_width.to_double() * atlas_height.to_double() +
      width.to_double() * height.to_double() * 2.0
    ) *
    4.0
  if bytes.is_nan() ||
    bytes.is_inf() ||
    bytes > max_bytes ||
    atlas_height > 4096 {
    return None
  }
  Some({
    size,
    stroke_width,
    glyph_count,
    metrics,
    x: -metrics.width / 2.0 - padding,
    y: -metrics.height / 2.0 - padding,
    width,
    height,
    columns,
    cell_count,
    atlas_width,
    atlas_height,
    scale,
    bytes,
  })
}

///|
pub fn atlas_cell(plan : TextAtlasPlan, index : Int) -> (Double, Double) {
  (
    (index % plan.columns * plan.width).to_double(),
    (index / plan.columns * plan.height).to_double(),
  )
}

///|
pub fn text_atlas_svg(
  plan : TextAtlasPlan,
  item : Drawable,
  font_styles : String,
) -> String {
  let complete = { ..item, progress: 1.0, }
  let cells = StringBuilder()
  // All masks shape the same complete lines. Measure once per atlas, not per mask.
  let measure = fn(_, _) { plan.metrics }
  for index = 0; index < plan.cell_count; index = index + 1 {
    let (x, y) = atlas_cell(plan, index)
    let glyph = index / 2 - 1
    let opacity = if glyph < 0 {
      None
    } else {
      Some(fn(candidate) { if candidate == glyph { 1.0 } else { 0.0 } })
    }
    let body = text_markup(
      complete,
      "text-mask-\{index}",
      measure,
      glyph_opacity?=opacity,
    )
    let paint = if index % 2 == 0 {
      "fill=\"white\" stroke=\"none\""
    } else {
      "fill=\"none\" stroke=\"white\" stroke-width=\"\{number(plan.stroke_width)}\""
    }
    cells.write_string(
      "<svg x=\"\{x}\" y=\"\{y}\" width=\"\{plan.width}\" height=\"\{plan.height}\" viewBox=\"0 0 \{plan.width.to_double() / plan.scale} \{plan.height.to_double() / plan.scale}\"><g transform=\"translate(\{number(-plan.x)} \{number(-plan.y)})\" \{paint} stroke-linecap=\"round\" stroke-linejoin=\"round\">\{body}</g></svg>",
    )
  }
  "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"\{plan.atlas_width}\" height=\"\{plan.atlas_height}\" viewBox=\"0 0 \{plan.atlas_width} \{plan.atlas_height}\">\{font_styles}\{cells.to_string()}</svg>"
}
