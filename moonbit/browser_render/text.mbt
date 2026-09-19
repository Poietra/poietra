///|
let color_glyphs : @regexp.RegExp = @regexp.RegExp::new(
  "[\\p{Extended_Pictographic}\\p{Regional_Indicator}\\p{Emoji_Presentation}\\uFE0F\\u20E3]",
  flags="u",
)

///|
pub fn text_drawing_key(item : @core.Any, scale : Double) -> @core.Any {
  let kind : String = item._get("object")._get("kind").cast()
  let state = item._get("state")
  let text : String = state._get("text").cast()
  if !(kind == "text" ||
    (kind == "equation" && @core.is_nullish(get_equation(text)))) ||
    color_glyphs.test_(text) {
    return @core.null()
  }
  @core.any(
    @core.json_stringify(
      @core.any(
        (
          [
            @core.any(text),
            @core.any(@render.finite(state._get("fontSize").cast()).max(0.0)),
            @core.any(@render.finite(state._get("strokeWidth").cast()).max(0.0)),
            item._get("order"),
            @core.any(scale),
          ] : FixedArray[@core.Any]),
      ),
    ),
  )
}

///|
priv struct Surface {
  canvas : @core.Any
  context : @canvas.CanvasRenderingContext2D
}

///|
fn release_surface(surface : Surface) -> Unit {
  surface.canvas._set("width", @core.any(0))
  surface.canvas._set("height", @core.any(0))
}

///|
fn create_surface(width : Int, height : Int) -> Surface {
  let canvas = @core.global_this()
    ._get("document")
    ._call("createElement", [@core.any("canvas")])
  canvas._set("width", @core.any(width))
  canvas._set("height", @core.any(height))
  let context = canvas._call("getContext", [@core.any("2d")])
  if @core.is_nullish(context) {
    canvas._set("width", @core.any(0))
    canvas._set("height", @core.any(0))
    return unsupported(
      "文字を描画する Canvas を作成できませんでした。",
    )
  }
  { canvas, context: context.cast(), }
}

///|
fn atlas_metrics(value : @core.Any) -> @render.TextMetrics {
  {
    width: value._get("width").cast(),
    height: value._get("height").cast(),
    line_height: value._get("lineHeight").cast(),
    baseline: value._get("baseline").cast(),
  }
}

///|
pub fn prepare_text_drawing(
  item : @core.Any,
  scale : Double,
  max_bytes : Double,
  signal : @core.Any,
) -> @core.Promise[@core.Any] {
  @core.from_async(async fn() {
    @core.throwable(fn() { signal._call("throwIfAborted", []) }) |> ignore
    let key = text_drawing_key(item, scale)
    if @core.is_nullish(key) || scale.is_nan() || scale.is_inf() || scale <= 0.0 {
      return @core.null()
    }
    let drawable = @boundary.decode_drawable(item)
    let metrics = atlas_metrics(
      measure_text(
        drawable.state.text,
        @render.finite(drawable.state.fontSize).max(0.0),
      ),
    )
    guard @render.text_atlas_plan(drawable, metrics, scale, max_bytes)
      is Some(plan) else {
      return @core.null()
    }
    let svg = @render.text_atlas_svg(
      plan,
      drawable,
      embedded_font_styles([drawable.state.text]),
    )
    let surfaces : Array[Surface] = []
    let alive = Ref(true)
    let dispose = fn() {
      alive.val = false
      for surface in surfaces {
        release_surface(surface)
      }
      surfaces.clear()
    }
    errdefer dispose()
    let surface = fn(width, height) {
      let value = create_surface(width, height)
      surfaces.push(value)
      value
    }
    let (atlas, tint, glyph) = @core.throwable(fn() {
      (
        surface(plan.atlas_width, plan.atlas_height),
        surface(plan.width, plan.height),
        surface(plan.width, plan.height),
      )
    })
    with_svg_image(svg, signal, fn(image) {
      atlas.context.drawImage(image, 0.0, 0.0)
      @core.undefined()
    }).wait()
    |> ignore
    let width = plan.width.to_double()
    let height = plan.height.to_double()
    fn paint_mask(index : Int, value : String, fallback : String) -> Unit {
      let css = @render.color(value)
      if css.to_lower() == "none" {
        return
      }
      let (x, y) = @render.atlas_cell(plan, index)
      saved_canvas(tint.context, fn() {
        tint.context.clearRect(0.0, 0.0, width, height)
        tint.context.drawImageSub(
          atlas.canvas,
          x,
          y,
          width,
          height,
          0.0,
          0.0,
          width,
          height,
        )
        tint.context
        .as_any()
        ._set("globalCompositeOperation", @core.any("source-in"))
        tint.context.fillStyle = fallback
        tint.context.fillStyle = css
        tint.context.fillRect(0.0, 0.0, width, height)
      })
      glyph.context.drawImage(tint.canvas, 0.0, 0.0)
    }
    fn paint_cell(
      context : @canvas.CanvasRenderingContext2D,
      item : @core.Any,
      index : Int,
      opacity : Double,
    ) -> Unit {
      if opacity <= 0.0 {
        return
      }
      glyph.context.clearRect(0.0, 0.0, width, height)
      let state = item._get("state")
      paint_mask(index * 2, state._get("fill").cast(), "#000000")
      if plan.stroke_width > 0.0 {
        paint_mask(index * 2 + 1, state._get("stroke").cast(), "transparent")
      }
      let previous_alpha = context.globalAlpha
      context.globalAlpha *= opacity
      context.drawImageScaled(
        glyph.canvas,
        plan.x,
        plan.y,
        width / scale,
        height / scale,
      )
      context.globalAlpha = previous_alpha
    }
    @core.from_entries([
      ("key", key),
      ("bytes", @core.any(plan.bytes)),
      ("dispose", @core.any(dispose)),
      (
        "paint",
        @core.any(fn(value : @core.Any, current : @core.Any) {
          let progress = @render.unit(current._get("writeProgress").cast())
          if !alive.val || progress == 0.0 || plan.size == 0.0 {
            return
          }
          let order : String = current._get("order").cast()
          let context : @canvas.CanvasRenderingContext2D = value.cast()
          saved_canvas(context, fn() {
            if order == "together" && progress < 1.0 {
              let padding = plan.size * 0.2
              context.beginPath()
              context.rect(
                -metrics.width / 2.0,
                -metrics.height / 2.0 - padding,
                metrics.width * progress,
                metrics.height + padding * 2.0,
              )
              context.clip()
            }
            if order == "sequential" && progress < 1.0 {
              for index = 0; index < plan.glyph_count; index = index + 1 {
                paint_cell(
                  context,
                  current,
                  index + 1,
                  @render.unit(
                    progress * plan.glyph_count.to_double() - index.to_double(),
                  ),
                )
              }
            } else {
              paint_cell(context, current, 0, 1.0)
            }
          })
        }),
      ),
    ])
  })
  |> host_errors
}
