///|
fn decode_arrow(value : @core.Any) -> @render.ArrowGeometry {
  {
    length: value._get("length").cast(),
    angle: value._get("angle").cast(),
    head: value._get("head").cast(),
    spread: value._get("spread").cast(),
  }
}

///|
fn decode_shape(value : @core.Any) -> @render.Shape? {
  if @core.is_nullish(value) {
    return None
  }
  let kind : String = value._get("kind").cast()
  match kind {
    "circle" =>
      Some(
        @render.Ellipse(
          value._get("radiusX").cast(),
          value._get("radiusY").cast(),
        ),
      )
    "rectangle" =>
      Some(
        @render.Rectangle(
          value._get("width").cast(),
          value._get("height").cast(),
          value._get("radius").cast(),
        ),
      )
    "path" => Some(@render.Path(value._get("path").cast()))
    "arrow" => Some(@render.Arrow(decode_arrow(value)))
    "numberline" => Some(@render.NumberLine(decode_arrow(value)))
    _ => None
  }
}

///|
let prepared_shapes : @core.Any = @core.new(
  @core.global_this()._get("WeakMap"),
  [],
)

///|
fn paint_shape(
  context : @canvas.CanvasRenderingContext2D,
  item : @core.Any,
  shape : @render.Shape,
  drawing : Outline,
  head : CanvasPath?,
  ticks : Array[CanvasPath],
) -> Unit {
  let progress = @render.unit(item._get("writeProgress").cast())
  if progress == 0.0 {
    return
  }
  let state = item._get("state")
  let fill = @render.color(state._get("fill").cast())
  let stroke = @render.color(state._get("stroke").cast())
  let stroke_width = @render.finite(state._get("strokeWidth").cast()).max(0.0)
  saved_canvas(context, fn() {
    let opacity = context.globalAlpha
    context.fillStyle = "#000000"
    context.strokeStyle = "transparent"
    context.fillStyle = fill
    context.strokeStyle = stroke
    round_caps(context)
    if stroke_width > 0.0 {
      context.lineWidth = stroke_width
    }
    match shape {
      Arrow(geometry) | NumberLine(geometry) =>
        context.rotate(
          numeric_string(@render.number(geometry.angle)) * @math.PI / 180.0,
        )
      _ => ()
    }
    if (shape is Ellipse(_, _) || shape is Rectangle(_, _, _)) &&
      fill.to_lower() != "none" {
      context.globalAlpha = opacity * progress
      fill_path(context, drawing.path)
    }
    if stroke.to_lower() != "none" && stroke_width > 0.0 {
      context.globalAlpha = opacity
      canvas_dash(
        context,
        if progress < 1.0 && drawing.length > 0.0 {
          [drawing.length, drawing.length]
        } else {
          []
        },
        if progress < 1.0 {
          (1.0 - progress) * drawing.length
        } else {
          0.0
        },
      )
      stroke_path(context, drawing.path)
      canvas_dash(context, [], 0.0)
      for index, tick in ticks {
        context.globalAlpha = opacity *
          @render.numberline_tick_progress(progress, index)
        stroke_path(context, tick)
      }
      if head is Some(head) {
        context.globalAlpha = opacity * @render.arrow_head_progress(progress)
        stroke_path(context, head)
      }
    }
  })
}

///|
pub fn prepare_shape_drawing(
  value : @core.Any,
  previous : @core.Any,
) -> @core.Any {
  if !canvas_available() {
    return @core.null()
  }
  guard decode_shape(value) is Some(shape) else { return @core.null() }
  // Compare typed geometry before allocating a serialized cache key on every frame.
  let cached = prepared_shapes._call("get", [previous])
  if !@core.is_undefined(cached) {
    let cached : @render.Shape = cached.cast()
    if cached == shape {
      return previous
    }
  }
  let key = @core.json_stringify(value)
  if !@core.is_nullish(previous) &&
    @core.equal(previous._get("key"), @core.any(key)) {
    return previous
  }
  @core.throwable(fn() {
    let drawing = outline(shape)
    let head = match shape {
      Arrow(geometry) | NumberLine(geometry) =>
        Some(canvas_path(@render.arrow_head_path(geometry)))
      _ => None
    }
    let ticks = match shape {
      NumberLine(geometry) =>
        Array::makei(11, fn(index) {
          canvas_path(@render.numberline_tick_path(geometry.length, index))
        })
      _ => []
    }
    let result = @core.from_entries([
      ("key", @core.any(key)),
      ("sourceBytes", @core.any(key.length() * 2)),
      (
        "paint",
        @core.any(fn(context : @core.Any, item : @core.Any) {
          paint_shape(context.cast(), item, shape, drawing, head, ticks)
        }),
      ),
    ])
    prepared_shapes._call("set", [result, @core.any(shape)]) |> ignore
    result
  }) catch {
    _ => @core.null()
  }
}
