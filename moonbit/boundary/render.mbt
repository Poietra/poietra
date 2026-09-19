///|
fn write_order(value : @core.Any) -> @render.WriteOrder {
  if strict_equal(value, @core.any("sequential")) {
    @render.Sequential
  } else {
    @render.Together
  }
}

///|
pub fn decode_drawable(value : @core.Any) -> @render.Drawable {
  let object = value._get("object")
  let image = optional(object._get("image"), fn(v) { v._get("src").cast() })
  {
    id: object._get("id").cast(),
    kind: decode_ObjectKind(object._get("kind")),
    state: decode_ObjectState(value._get("state")),
    progress: value._get("writeProgress").cast(),
    order: write_order(value._get("order")),
    image,
    video_frame: optional(value._get("videoFrame"), fn(v) { v.cast() }),
  }
}

///|
fn decode_math_node(value : @core.Any) -> @render.MathNode {
  let attributes = value._get("attributes")
  {
    tag: @render.math_tag(value._get("tag").cast()).unwrap(),
    attributes: @core.object_keys(attributes).map(fn(key) {
      (key, attributes._get(key).cast())
    }),
    children: decode_array(value._get("children"), decode_math_node),
  }
}

///|
// MathJax trees are immutable after preparation; their typed view shares that lifetime.
let equation_views : WeakCache[@render.Equation] = WeakCache::new()

///|
fn decode_equation(value : @core.Any) -> @render.Equation {
  if equation_views.has(value) {
    return equation_views.get(value)
  }
  let result : @render.Equation = {
    x: value._get("x").cast(),
    y: value._get("y").cast(),
    width: value._get("width").cast(),
    height: value._get("height").cast(),
    tree: decode_math_node(value._get("tree")),
    glyphs: value._get("glyphs").cast(),
  }
  equation_views.set(value, result)
  result
}

///|
fn decode_text_metrics(value : @core.Any) -> @render.TextMetrics {
  {
    width: value._get("width").cast(),
    height: value._get("height").cast(),
    line_height: value._get("lineHeight").cast(),
    baseline: value._get("baseline").cast(),
  }
}

///|
pub fn render_resources(host : @core.Any) -> @render.Resources {
  {
    equation: fn(text) {
      optional(host._call("getEquation", [@core.any(text)]), decode_equation)
    },
    measure_text: fn(text, size) {
      decode_text_metrics(
        host._call("measureText", [@core.any(text), @core.any(size)]),
      )
    },
    image: fn(source) {
      optional(host._call("preparedImage", [@core.from_option(source)]), fn(v) {
        v.cast()
      })
    },
    font_styles: fn(sources) {
      host
      ._call("embeddedFontStyles", [
        @core.any(FixedArray::from_array(sources[:])),
      ])
      .cast()
    },
  }
}

///|
pub fn prepare_render_scene(
  scene : @core.Any,
  host : @core.Any,
) -> @core.Promise[Unit] {
  @core.from_async(async fn() {
    let images : @core.Promise[Unit] = host
      ._call("prepareImages", [scene])
      .cast()
    images.wait()
    let objects = scene._get("objects")
    let compositions = scene._get("compositions")
    let equation_ids = @core.object_keys(objects).filter(fn(id) {
      strict_equal(objects._get(id)._get("kind"), @core.any("equation"))
    })
    let equations = []
    for key in @core.object_keys(compositions) {
      let states = compositions._get(key)._get("states")
      for id in equation_ids {
        let state = states._get(id)
        if !@core.is_nullish(state) {
          equations.push(state._get("text"))
        }
      }
    }
    let preparation : @core.Promise[Unit] = host
      ._call("prepareEquations", [
        @core.any(FixedArray::from_array(equations[:])),
      ])
      .cast()
    preparation.wait()
    let text_ids = @core.object_keys(objects).filter(fn(id) {
      let kind = objects._get(id)._get("kind")
      strict_equal(kind, @core.any("text")) ||
      strict_equal(kind, @core.any("equation"))
    })
    let sources = []
    for key in @core.object_keys(compositions) {
      let states = compositions._get(key)._get("states")
      for id in text_ids {
        let state = states._get(id)
        if @core.is_nullish(state) {
          continue
        }
        let text = state._get("text")
        if strict_equal(objects._get(id)._get("kind"), @core.any("text")) ||
          @core.is_nullish(host._call("getEquation", [text])) {
          sources.push(text)
        }
      }
    }
    let fonts : @core.Promise[Unit] = host
      ._call("prepareFonts", [@core.any(FixedArray::from_array(sources[:]))])
      .cast()
    fonts.wait()
  })
}

///|
let svg_sequence : Ref[Int] = Ref(0)

///|
pub fn frame_to_svg(
  frame : @core.Any,
  options : @core.Any,
  host : @core.Any,
) -> String {
  let prefix = if @core.is_nullish(options._get("idPrefix")) {
    let value = "frame-\{svg_sequence.val}"
    svg_sequence.val += 1
    value
  } else {
    options._get("idPrefix").cast()
  }
  @render.frame_to_svg(
    {
      width: frame._get("width").cast(),
      height: frame._get("height").cast(),
      background: frame._get("background").cast(),
      objects: decode_array(frame._get("objects"), decode_drawable),
    },
    prefix,
    !strict_equal(options._get("background"), @core.any(false)),
    render_resources(host),
    video_hits=strict_equal(options._get("hitVideo"), @core.any(true)),
  )
}

///|
extern "js" fn bounds_value(
  x : Double,
  y : Double,
  width : Double,
  height : Double,
) -> @core.Any =
  #|(x, y, width, height) => ({x, y, width, height})

///|
pub fn object_bounds(item : @core.Any, host : @core.Any) -> @core.Any {
  let result = @render.object_bounds(
    decode_drawable(item),
    render_resources(host),
  )
  bounds_value(result.x, result.y, result.width, result.height)
}

///|
pub fn text_markup(
  item : @core.Any,
  prefix : String,
  opacity : @core.Any,
  measure : (String, Double) -> @core.Any,
) -> String {
  @render.text_markup(
    decode_drawable(item),
    prefix,
    fn(text, size) { decode_text_metrics(measure(text, size)) },
    glyph_opacity?=optional(opacity, fn(v) { v.cast() }),
  )
}

///|
pub fn equation_markup(
  equation : @core.Any,
  progress : Double,
  order : @core.Any,
) -> String {
  @render.equation_markup(
    decode_equation(equation),
    progress,
    write_order(order),
  )
}

///|
pub fn equation_glyph_progress(
  progress : Double,
  order : @core.Any,
  glyphs : Int,
  index : Int,
) -> Double {
  @render.equation_glyph_progress(progress, write_order(order), glyphs, index)
}

///|
pub fn equation_fill_progress(progress : Double) -> Double {
  @render.equation_fill_progress(progress)
}

///|
pub fn svg_color(value : String, fallback : @core.Any) -> String {
  @render.color(value, fallback?=optional(fallback, fn(v) { v.cast() }))
}

///|
pub fn svg_escape(value : String) -> String {
  @render.escape_xml(value)
}

///|
pub fn svg_finite(value : Double, fallback : @core.Any) -> Double {
  @render.finite(value, fallback?=optional(fallback, fn(v) { v.cast() }))
}

///|
pub fn svg_unit(value : Double) -> Double {
  @render.unit(value)
}

///|
pub fn svg_number(value : Double) -> String {
  @render.number(value)
}

///|
pub fn svg_id(value : String) -> String {
  @render.safe_id(value)
}

///|
extern "js" fn ellipse_value(x : Double, y : Double) -> @core.Any =
  #|(radiusX, radiusY) => ({kind: 'circle', radiusX, radiusY})

///|
extern "js" fn shape_rectangle_value(
  width : Double,
  height : Double,
  radius : Double,
) -> @core.Any =
  #|(width, height, radius) => ({kind: 'rectangle', width, height, radius})

///|
extern "js" fn path_value(path : String) -> @core.Any =
  #|path => ({kind: 'path', path})

///|
extern "js" fn arrow_value(
  kind : String,
  length : Double,
  angle : Double,
  head : Double,
  spread : Double,
) -> @core.Any =
  #|(kind, length, angle, head, spread) => ({kind, length, angle, head, spread})

///|
pub fn shape_geometry(item : @core.Any) -> @core.Any {
  let kind = decode_ObjectKind(item._get("object")._get("kind"))
  match @render.shape_geometry(kind, decode_ObjectState(item._get("state"))) {
    None => @core.null()
    Some(Ellipse(x, y)) => ellipse_value(x, y)
    Some(Rectangle(width, height, radius)) =>
      shape_rectangle_value(width, height, radius)
    Some(Path(path)) => path_value(path)
    Some(Arrow(geometry) | NumberLine(geometry)) =>
      arrow_value(
        @scene.object_kind_name(kind),
        geometry.length,
        geometry.angle,
        geometry.head,
        geometry.spread,
      )
  }
}

///|
pub fn arrow_head_path(shape : @core.Any) -> String {
  @render.arrow_head_path({
    length: shape._get("length").cast(),
    angle: shape._get("angle").cast(),
    head: shape._get("head").cast(),
    spread: shape._get("spread").cast(),
  })
}

///|
pub fn arrow_head_progress(progress : Double) -> Double {
  @render.arrow_head_progress(progress)
}

///|
pub fn numberline_tick_path(length : Double, index : Int) -> String {
  @render.numberline_tick_path(length, index)
}

///|
pub fn numberline_tick_progress(progress : Double, index : Int) -> Double {
  @render.numberline_tick_progress(progress, index)
}
