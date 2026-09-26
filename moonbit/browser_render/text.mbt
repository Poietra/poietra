///|
let color_glyphs : @regexp.RegExp = @regexp.RegExp::new(
  "[\\p{Extended_Pictographic}\\p{Regional_Indicator}\\p{Emoji_Presentation}\\uFE0F\\u20E3]",
  flags="u",
)

///|
fn text_key(item : @render.Drawable, scale : Double) -> String? {
  let text = item.state.text
  if !(item.kind == @scene.Text ||
    (item.kind == @scene.Equation && @core.is_nullish(get_equation(text)))) ||
    color_glyphs.test_(text) {
    return None
  }
  Some(
    @core.json_stringify(
      @core.any(
        (
          [
            @core.any(text),
            @core.any(@render.finite(item.state.fontSize).max(0.0)),
            @core.any(@render.finite(item.state.strokeWidth).max(0.0)),
            @core.any(
              if item.order == @render.Sequential {
                "sequential"
              } else {
                "together"
              },
            ),
            @core.any(scale),
          ] : FixedArray[@core.Any]),
      ),
    ),
  )
}

///|
pub fn text_drawing_key(item : @core.Any, scale : Double) -> @core.Any {
  @core.from_option(text_key(@boundary.decode_drawable(item), scale))
}

///|
priv struct TextPaint {
  fill : String
  stroke : String
  progress : Double
  order : @render.WriteOrder
}

///|
priv struct TextDrawing {
  key : String
  bytes : Double
  dispose : () -> Unit
  paint : (@canvas.CanvasRenderingContext2D, TextPaint) -> Unit
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
fn prepare_text(
  drawable : @render.Drawable,
  scale : Double,
  max_bytes : Double,
  signal : @core.Any,
) -> @core.Promise[TextDrawing?] {
  @core.from_async(async fn() {
    @core.throwable(fn() { signal._call("throwIfAborted", []) }) |> ignore
    guard text_key(drawable, scale) is Some(key) else { return None }
    if scale.is_nan() || scale.is_inf() || scale <= 0.0 {
      return None
    }
    let metrics = atlas_metrics(
      measure_text(
        drawable.state.text,
        @render.finite(drawable.state.fontSize).max(0.0),
      ),
    )
    guard @render.text_atlas_plan(drawable, metrics, scale, max_bytes)
      is Some(plan) else {
      return None
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
      item : TextPaint,
      index : Int,
      opacity : Double,
    ) -> Unit {
      if opacity <= 0.0 {
        return
      }
      glyph.context.clearRect(0.0, 0.0, width, height)
      paint_mask(index * 2, item.fill, "#000000")
      if plan.stroke_width > 0.0 {
        paint_mask(index * 2 + 1, item.stroke, "transparent")
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
    Some(TextDrawing::{
      key,
      bytes: plan.bytes,
      dispose,
      paint: fn(context, current) {
        let progress = @render.unit(current.progress)
        if !alive.val || progress == 0.0 || plan.size == 0.0 {
          return
        }
        let order = current.order
        saved_canvas(context, fn() {
          if order == @render.Together && progress < 1.0 {
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
          if order == @render.Sequential && progress < 1.0 {
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
      },
    })
  })
  |> host_errors
}

///|
fn text_paint(item : @render.Drawable) -> TextPaint {
  {
    fill: item.state.fill,
    stroke: item.state.stroke,
    progress: item.progress,
    order: item.order,
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
    let item = @core.throwable(fn() { @boundary.decode_drawable(item) })
    guard prepare_text(item, scale, max_bytes, signal).wait() is Some(drawing) else {
      return @core.null()
    }
    @core.from_entries([
      ("key", @core.any(drawing.key)),
      ("bytes", @core.any(drawing.bytes)),
      ("dispose", @core.any(drawing.dispose)),
      (
        "paint",
        @core.any(fn(context : @core.Any, input : @core.Any) {
          let state = input._get("state")
          (drawing.paint)(context.cast(), {
            fill: state._get("fill").cast(),
            stroke: state._get("stroke").cast(),
            progress: input._get("writeProgress").cast(),
            order: if @core.equal(input._get("order"), @core.any("sequential")) {
              @render.Sequential
            } else {
              @render.Together
            },
          })
        }),
      ),
    ])
  })
  |> host_errors
}
