///|
priv struct RasterIdentity {
  item : @render.Drawable
  media : String?
  video_time : Double?
  scale : Double
  glow : Bool
} derive(Eq)

///|
priv struct PreparedEquation {
  source : @core.Any
  drawing : @core.Any
}

///|
/// Cache entries and in-flight requests each hold one lease. Eviction cannot
/// destroy a text atlas while an asynchronous replacement still uses it.
priv struct TextMasks {
  drawing : @core.Any
  mut leases : Int
}

///|
priv struct PreparedText {
  key : String
  masks : TextMasks?
}

///|
priv struct CachedRaster {
  identity : RasterIdentity
  canvas : @core.Any
  result : @core.Any
  bytes : Double
  equation : PreparedEquation?
  shape : @core.Any
  text : PreparedText?
}

///|
priv struct RasterCache {
  entries : Map[String, CachedRaster]
  pending : Map[String, Ref[Bool]]
  resources : @render.Resources
  mut bytes : Double
  mut source : @core.Any?
}

///|
extern "js" fn copy_record(value : @core.Any) -> @core.Any =
  #|value => ({...value})

///|
fn native_canvas() -> @core.Any {
  @core.global_this()
  ._get("document")
  ._call("createElement", [@core.any("canvas")])
}

///|
fn release_canvas(canvas : @core.Any) -> Unit {
  canvas._set("width", @core.any(0))
  canvas._set("height", @core.any(0))
}

///|
fn release_masks(text : PreparedText?) -> Unit {
  if text is Some({ masks: Some(masks), .. }) {
    masks.leases -= 1
    if masks.leases == 0 {
      masks.drawing._call("dispose", []) |> ignore
    }
  }
}

///|
fn RasterCache::remove(self : RasterCache, id : String) -> Unit {
  if self.entries.get(id) is Some(entry) {
    self.entries.remove(id)
    self.bytes -= entry.bytes
    release_canvas(entry.canvas)
    release_masks(entry.text)
  }
}

///|
fn RasterCache::clear(self : RasterCache) -> Unit {
  for _, ticket in self.pending {
    ticket.val = false
  }
  self.pending.clear()
  for _, entry in self.entries {
    release_canvas(entry.canvas)
    release_masks(entry.text)
  }
  self.entries.clear()
  self.bytes = 0.0
  if self.source is Some(canvas) {
    release_canvas(canvas)
  }
  self.source = None
}

///|
fn RasterCache::retain(self : RasterCache, keep : (String) -> Bool) -> Unit {
  for id in self.entries.keys() {
    if !keep(id) {
      self.remove(id)
    }
  }
  for id in self.pending.keys() {
    if !keep(id) {
      if self.pending.get(id) is Some(ticket) {
        ticket.val = false
      }
      self.pending.remove(id)
    }
  }
}

///|
fn RasterCache::store(
  self : RasterCache,
  id : String,
  entry : CachedRaster,
) -> Unit {
  self.remove(id)
  while self.bytes + entry.bytes > @render.raster_cache_bytes {
    guard self.entries.iter().next() is Some((oldest, _)) else { break }
    self.remove(oldest)
  }
  self.entries[id] = entry
  self.bytes += entry.bytes
}

///|
fn raster_ticket(
  signal : @core.Any,
  ticket : Ref[Bool],
) -> Unit raise BrowserFailure {
  image_check_abort(signal)
  if !ticket.val {
    raise BrowserFailure(image_abort_error())
  }
}

///|
fn local_value(item : @core.Any) -> @core.Any {
  let result = copy_record(item)
  result._set("world", @core.undefined())
  let state = copy_record(item._get("state"))
  for field in ["anchorX", "anchorY", "scaleX", "scaleY", "shear"] {
    state._set(field, @core.undefined())
  }
  for field in ["x", "y", "rotation"] {
    state._set(field, @core.any(0.0))
  }
  state._set("opacity", @core.any(1.0))
  state._set("visible", @core.any(true))
  state._set("effect", @core.any("none"))
  result._set("state", state)
  result
}

///|
fn optional_number(value : @core.Any) -> Double? {
  if @core.is_nullish(value) {
    None
  } else {
    Some(value.cast())
  }
}

///|
fn optional_source(value : @core.Any) -> String? {
  if @core.is_nullish(value) {
    None
  } else {
    Some(value._get("src").cast())
  }
}

///|
fn drawing_bytes(drawing : @core.Any, field : String) -> Double {
  if @core.is_nullish(drawing) {
    0.0
  } else {
    drawing._get(field).cast()
  }
}

///|
fn equation_for(
  item : @render.Drawable,
  previous : PreparedEquation?,
) -> PreparedEquation? {
  if item.kind != @scene.Equation {
    return None
  }
  let source = get_equation(item.state.text)
  if @core.is_nullish(source) {
    return None
  }
  if previous is Some(previous) && @core.equal(previous.source, source) {
    return Some(previous)
  }
  Some({ source, drawing: prepare_equation_drawing(source), })
}

///|
fn layer_paint(
  item : @core.Any,
  equation : PreparedEquation?,
  shape : @core.Any,
  text : PreparedText?,
  video : @browser_media.VideoSurface?,
) -> ((@canvas.CanvasRenderingContext2D) -> Unit)? {
  if video is Some(video) {
    let drawable = @boundary.decode_drawable(item)
    return Some(fn(context) {
      let state = drawable.state
      let width = @render.finite(state.width).abs()
      let height = @render.finite(state.height).abs()
      let radius = @render.finite(state.cornerRadius)
        .max(0.0)
        .min(width / 2.0)
        .min(height / 2.0)
      let x = -width / 2.0
      let y = -height / 2.0
      saved_canvas(context, fn() {
        context.beginPath()
        context.rect(x, y, width * @render.unit(drawable.progress), height)
        context.clip()
        let path = @core.new(@core.global_this()._get("Path2D"), [])
        path._call("roundRect", [
          @core.any(x),
          @core.any(y),
          @core.any(width),
          @core.any(height),
          @core.any(radius),
        ])
        |> ignore
        saved_canvas(context, fn() {
          context.as_any()._call("clip", [path]) |> ignore
          context.drawImageScaled(video.canvas, x, y, width, height)
        })
        let stroke = @render.color(state.stroke)
        let stroke_width = @render.finite(state.strokeWidth).max(0.0)
        if stroke != "none" && stroke_width > 0.0 {
          context.strokeStyle = stroke
          context.lineWidth = stroke_width
          round_caps(context)
          context.as_any()._call("stroke", [path]) |> ignore
        }
      })
    })
  }
  if equation is Some({ source, drawing, }) && !@core.is_nullish(drawing) {
    return Some(fn(context) {
      let state = item._get("state")
      let scale = @render.finite(state._get("fontSize").cast()).max(0.0) /
        1000.0
      context.scale(scale, scale)
      let x : Double = source._get("x").cast()
      let y : Double = source._get("y").cast()
      let width : Double = source._get("width").cast()
      let height : Double = source._get("height").cast()
      context.translate(-x - width / 2.0, -y - height / 2.0)
      drawing._call("paint", [
        context.as_any(),
        item._get("writeProgress"),
        item._get("order"),
        @core.any(@render.color(state._get("fill").cast(), fallback="#d7d8e4")),
      ])
      |> ignore
    })
  }
  if !@core.is_nullish(shape) {
    return Some(fn(context) {
      shape._call("paint", [context.as_any(), item]) |> ignore
    })
  }
  if text is Some({ masks: Some(masks), .. }) {
    return Some(fn(context) {
      masks.drawing._call("paint", [context.as_any(), item]) |> ignore
    })
  }
  None
}

///|
fn paint_layer_source(
  canvas : @core.Any,
  plan : @render.RasterPlan,
  scale : Double,
  paint : (@canvas.CanvasRenderingContext2D) -> Unit,
) -> Unit {
  resize_canvas(canvas, plan.width, plan.height)
  let context = layer_context(canvas)
  context.resetTransform()
  context.clearRect(0.0, 0.0, plan.width.to_double(), plan.height.to_double())
  saved_canvas(context, fn() {
    context.scale(scale, scale)
    context.translate(-plan.bounds.x, -plan.bounds.y)
    paint(context)
  })
}

///|
/// Shrink first so aspect-ratio changes never transiently allocate both larger axes.
fn resize_canvas(canvas : @core.Any, width : Int, height : Int) -> Unit {
  let previous_width : Int = canvas._get("width").cast()
  let previous_height : Int = canvas._get("height").cast()
  if width < previous_width {
    canvas._set("width", @core.any(width))
  }
  if height < previous_height {
    canvas._set("height", @core.any(height))
  }
  if width > previous_width {
    canvas._set("width", @core.any(width))
  }
  if height > previous_height {
    canvas._set("height", @core.any(height))
  }
}

///|
fn layer_context(canvas : @core.Any) -> @canvas.CanvasRenderingContext2D {
  let context = canvas._call("getContext", [@core.any("2d")])
  if @core.is_nullish(context) {
    return unsupported(
      "オブジェクトを描画する Canvas を作成できませんでした。",
    )
  }
  context.cast()
}

///|
fn glow_lost(glow : @core.Any) -> Bool {
  glow._get("lost").cast()
}

///|
fn copy_layer(
  source : @core.Any,
  plan : @render.RasterPlan,
  glow : @core.Any,
  has_glow : Bool,
  scale : Double,
) -> @core.Any? raise {
  if glow_lost(glow) {
    return None
  }
  if has_glow {
    let success = @core.throwable(fn() {
      glow._call("render", [
        source,
        @core.any(plan.width),
        @core.any(plan.height),
        @core.any(4.0 * scale),
      ])
      |> ignore
      true
    }) catch {
      _ => false
    }
    if !success {
      return None
    }
  }
  let canvas = @core.throwable(native_canvas)
  errdefer release_canvas(canvas)
  @core.throwable(fn() {
    resize_canvas(canvas, plan.width, plan.height)
    layer_context(canvas).drawImage(
      if has_glow {
        glow._get("canvas")
      } else {
        source
      },
      0.0,
      0.0,
    )
  })
  Some(canvas)
}

///|
async fn rasterize_layer(
  cache : RasterCache,
  plan : @render.RasterPlan,
  identity : RasterIdentity,
  item : @core.Any,
  equation : PreparedEquation?,
  shape : @core.Any,
  text : PreparedText?,
  video : @browser_media.VideoSurface?,
  glow : @core.Any,
  signal : @core.Any,
) -> @core.Any? {
  if layer_paint(item, equation, shape, text, video) is Some(paint) {
    let source = match cache.source {
      Some(source) => source
      None => {
        let source = @core.throwable(native_canvas)
        cache.source = Some(source)
        source
      }
    }
    @core.throwable(fn() {
      paint_layer_source(source, plan, identity.scale, paint)
    })
    return copy_layer(source, plan, glow, identity.glow, identity.scale)
  }
  let drawable = {
    ..identity.item,
    state: { ..identity.item.state, x: -plan.bounds.x, y: -plan.bounds.y, },
  }
  let svg = @core.throwable(fn() {
    @render.frame_to_svg(
      {
        width: plan.bounds.width,
        height: plan.bounds.height,
        background: "transparent",
        objects: [drawable],
      },
      "painter-layer",
      false,
      cache.resources,
    )
  })
  let header_end = svg.find(">").unwrap() + 1
  let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"\{plan.width}\" height=\"\{plan.height}\" viewBox=\"0 0 \{plan.bounds.width} \{plan.bounds.height}\">" +
    svg[header_end:].to_owned()
  let output : Ref[@core.Any?] = Ref(None)
  errdefer (if output.val is Some(canvas) { release_canvas(canvas) })
  // The synchronous callback is a host boundary; preserve native exception identity.
  with_svg_image(svg, signal, fn(source) {
    try {
      output.val = copy_layer(source, plan, glow, identity.glow, identity.scale)
    } catch {
      error => native_throw(host_error(error))
    }
    @core.undefined()
  }).wait()
  |> ignore
  output.val
}

///|
async fn RasterCache::get(
  self : RasterCache,
  input : @core.Any,
  scale : Double,
  glow : @core.Any,
  signal : @core.Any,
  video? : @browser_media.VideoSurface? = None,
) -> @core.Any {
  image_check_abort(signal)
  let drawable = @boundary.decode_drawable(input)
  let enlargement = match drawable.world {
    Some(matrix) => matrix.max_scale()
    None =>
      if drawable.state.has_transform() {
        drawable.state.local_matrix().max_scale()
      } else {
        1.0
      }
  }
  // Scale in whole-density steps to retain sharp enlarged text/curves without
  // invalidating their rasters for every fractional transform during playback.
  let scale = scale * (enlargement - 1.0e-9).ceil().max(1.0)
  let id = drawable.id
  if self.pending.get(id) is Some(previous) {
    previous.val = false
  }
  let ticket = Ref(true)
  self.pending[id] = ticket
  defer (if self.pending.get(id) is Some(current) &&
    physical_equal(current, ticket) {
    self.pending.remove(id)
  })
  let identity : RasterIdentity = {
    item: @render.local_drawable(drawable),
    scale,
    glow: drawable.state.effect == @scene.Glow,
    media: optional_source(input._get("object")._get("media")),
    video_time: match video {
      Some(v) => Some(v.timestamp)
      None => optional_number(input._get("videoTimeMs"))
    },
  }
  let previous = self.entries.get(id)
  if previous is Some(previous) && previous.identity == identity {
    self.entries.remove(id)
    self.entries[id] = previous
    return previous.result
  }
  let bounds = @core.throwable(fn() {
    @render.object_bounds(identity.item, self.resources)
  })
  guard @render.raster_plan(bounds, scale, identity.glow) is Some(plan) else {
    return @core.null()
  }
  let item = local_value(input)
  let equation = equation_for(
    identity.item,
    previous.bind(fn(p) { p.equation }),
  )
  let shape = prepare_shape_drawing(
    @boundary.shape_geometry(item),
    previous.map(fn(p) { p.shape }).unwrap_or(@core.undefined()),
  )
  let geometry_bytes = equation
    .map(fn(e) { drawing_bytes(e.drawing, "sourceBytes") })
    .unwrap_or(0.0) +
    drawing_bytes(shape, "sourceBytes")
  if plan.bytes + geometry_bytes > @render.raster_cache_bytes {
    return @core.null()
  }
  let mut text : PreparedText? = None
  let mut stored = false
  defer (if !stored { release_masks(text) })
  let text_key = text_drawing_key(item, scale)
  if !@core.is_nullish(text_key) {
    let key : String = text_key.cast()
    if previous.bind(fn(p) { p.text }) is Some(prepared) && prepared.key == key {
      if prepared.masks is Some(masks) {
        masks.leases += 1
      }
      text = Some(prepared)
    } else {
      let drawing = prepare_text_drawing(
        item,
        scale,
        @render.raster_cache_bytes - plan.bytes - geometry_bytes,
        signal,
      ).wait()
      text = Some({
        key,
        masks: if @core.is_nullish(drawing) {
          None
        } else {
          Some({ drawing, leases: 1, })
        },
      })
    }
  }
  raster_ticket(signal, ticket)
  let bytes = plan.bytes +
    geometry_bytes +
    text
    .bind(fn(t) { t.masks })
    .map(fn(m) { drawing_bytes(m.drawing, "bytes") })
    .unwrap_or(0.0)
  if bytes > @render.raster_cache_bytes {
    return @core.null()
  }
  guard rasterize_layer(
      self, plan, identity, item, equation, shape, text, video, glow, signal,
    )
    is Some(canvas) else {
    return @core.null()
  }
  errdefer release_canvas(canvas)
  raster_ticket(signal, ticket)
  let bounds = plan.bounds
  let result = @core.from_entries([
    ("canvas", canvas),
    (
      "sceneBounds",
      @core.from_entries([
        ("x", @core.any(bounds.x)),
        ("y", @core.any(bounds.y)),
        ("width", @core.any(bounds.width)),
        ("height", @core.any(bounds.height)),
      ]),
    ),
  ])
  self.store(id, { identity, canvas, result, bytes, equation, shape, text, })
  stored = true
  result
}

///|
fn new_raster_cache(resources : @core.Any) -> RasterCache {
  {
    entries: Map([]),
    pending: Map([]),
    resources: @boundary.render_resources(resources),
    bytes: 0.0,
    source: None,
  }
}

///|
pub fn create_layer_cache(resources : @core.Any) -> @core.Any {
  let cache = new_raster_cache(resources)
  @core.from_entries([
    ("clear", @core.any(fn() { cache.clear() })),
    (
      "retain",
      @core.any(fn(ids : @core.Any) {
        cache.retain(fn(id) { ids._call("has", [@core.any(id)]).cast() })
      }),
    ),
    (
      "get",
      @core.any(fn(
        item : @core.Any,
        scale : Double,
        glow : @core.Any,
        signal : @core.Any,
      ) {
        @core.from_async(async fn() { cache.get(item, scale, glow, signal) })
        |> host_errors
      }),
    ),
  ])
}
