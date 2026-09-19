///|
priv enum PainterBackend {
  Gpu(@core.Any)
  Svg
}

///|
priv struct FramePainter {
  target : Surface
  staging : Surface
  layers : RasterCache
  videos : @browser_media.VideoFrames
  lifetime : @core.Any
  mut backend : PainterBackend
}

///|
fn opaque_surface(canvas : @core.Any) -> Surface {
  let context = canvas._call("getContext", [
    @core.any("2d"),
    @core.from_entries([("alpha", @core.any(false))]),
  ])
  if @core.is_nullish(context) {
    return unsupported(
      "描画用の Canvas を初期化できませんでした。",
    )
  }
  { canvas, context: context.cast(), }
}

///|
fn FramePainter::use_svg(self : FramePainter) -> Unit {
  let previous = self.backend
  self.backend = Svg
  if previous is Gpu(glow) {
    glow._call("dispose", []) |> ignore
  }
  self.layers.clear()
}

///|
fn FramePainter::dispose(self : FramePainter) -> Unit {
  if aborted(self.lifetime._get("signal")) {
    return
  }
  self.lifetime._call("abort", [image_abort_error()]) |> ignore
  self.use_svg()
  self.videos.dispose()
  release_surface(self.staging)
}

///|
fn draw_layer(
  context : @canvas.CanvasRenderingContext2D,
  item : @render.Drawable,
  layer : @core.Any,
) -> Unit {
  let bounds = layer._get("sceneBounds")
  saved_canvas(context, fn() {
    if item.world is Some(matrix) {
      context
      .as_any()
      ._call("transform", [
        @core.any(matrix.a),
        @core.any(matrix.b),
        @core.any(matrix.c),
        @core.any(matrix.d),
        @core.any(matrix.e),
        @core.any(matrix.f),
      ])
      |> ignore
    } else if item.state.has_transform() {
      let matrix = item.state.local_matrix()
      context
      .as_any()
      ._call("transform", [
        @core.any(matrix.a),
        @core.any(matrix.b),
        @core.any(matrix.c),
        @core.any(matrix.d),
        @core.any(matrix.e),
        @core.any(matrix.f),
      ])
      |> ignore
    } else {
      context.translate(
        @render.finite(item.state.x),
        @render.finite(item.state.y),
      )
      context.rotate(@render.finite(item.state.rotation) * @math.PI / 180.0)
    }
    context.globalAlpha = @render.unit(item.state.opacity)
    context.drawImageScaled(
      layer._get("canvas"),
      bounds._get("x").cast(),
      bounds._get("y").cast(),
      bounds._get("width").cast(),
      bounds._get("height").cast(),
    )
  })
}

///|
async fn paint_layers(
  surface : Surface,
  frame : @render.RenderFrame,
  items : FixedArray[@core.Any],
  layers : RasterCache,
  glow : @core.Any,
  signal : @core.Any,
  videos : @browser_media.VideoSurfaces?,
) -> Bool {
  let context = surface.context
  let width : Double = surface.canvas._get("width").cast()
  let height : Double = surface.canvas._get("height").cast()
  let scale = (width / frame.width).min(height / frame.height)
  let ids : Map[String, Unit] = Map([])
  for item in frame.objects {
    ids[item.id] = ()
  }
  @core.throwable(fn() {
    context.fillStyle = "#000000"
    context.fillRect(0.0, 0.0, width, height)
    context.fillStyle = @render.color(frame.background, fallback="#08090b")
    context.fillRect(0.0, 0.0, width, height)
    layers.retain(fn(id) { ids.contains(id) })
    context.save()
  })
  defer context.restore()
  @core.throwable(fn() {
    context.translate(
      (width - frame.width * scale) / 2.0,
      (height - frame.height * scale) / 2.0,
    )
    context.scale(scale, scale)
    context.beginPath()
    context.rect(0.0, 0.0, frame.width, frame.height)
    context.clip()
  })
  for index, item in frame.objects {
    image_check_abort(signal)
    if !item.state.visible ||
      @render.unit(item.state.opacity) == 0.0 ||
      @render.unit(item.progress) == 0.0 {
      continue
    }
    let layer = layers.get(
      items[index],
      scale,
      glow,
      signal,
      video=videos.bind(fn(v) { v.get(item.id) }),
    )
    image_check_abort(signal)
    if @core.is_nullish(layer) || glow_lost(glow) {
      return false
    }
    @core.throwable(fn() { draw_layer(context, item, layer) })
  }
  !glow_lost(glow)
}

///|
fn commit_frame(
  target : @canvas.CanvasRenderingContext2D,
  staging : @core.Any,
) -> Unit {
  saved_canvas(target, fn() {
    target.resetTransform()
    target.globalAlpha = 1.0
    target.as_any()._set("globalCompositeOperation", @core.any("copy"))
    target.drawImage(staging, 0.0, 0.0)
  })
}

///|
fn combined_signal(lifetime : @core.Any, request : @core.Any) -> @core.Any {
  if @core.is_nullish(request) {
    lifetime
  } else {
    @core.global_this()
    ._get("AbortSignal")
    ._call("any", [@core.any(([lifetime, request] : FixedArray[@core.Any]))])
  }
}

///|
async fn FramePainter::render(
  self : FramePainter,
  input : @core.Any,
  options : @core.Any,
) -> Unit {
  let signal = combined_signal(
    self.lifetime._get("signal"),
    if @core.is_nullish(options) {
      @core.undefined()
    } else {
      options._get("signal")
    },
  )
  image_check_abort(signal)
  let input = @core.throwable(fn() {
    @core.global_this()._call("structuredClone", [input])
  })
  for
    dimension in [
      self.target.canvas._get("width"),
      self.target.canvas._get("height"),
      input._get("width"),
      input._get("height"),
    ] {
    let value : Double = dimension.cast()
    if value.is_nan() || value.is_inf() || value <= 0.0 {
      raise FontError(
        "Canvas とフレームの幅・高さを正の数にしてください。",
      )
    }
  }
  try {
    @core.throwable(fn() {
      resize_canvas(
        self.staging.canvas,
        self.target.canvas._get("width").cast(),
        self.target.canvas._get("height").cast(),
      )
    })
    let videos = if self.backend is Gpu(glow) && !glow_lost(glow) {
      Some(self.videos.prepare_canvas(input, signal).wait())
    } else {
      self.videos.prepare(input, signal).wait()
      None
    }
    defer (if videos is Some(videos) { videos.dispose() })
    image_check_abort(signal)
    let items : FixedArray[@core.Any] = input._get("objects").cast()
    let mut frame : @render.RenderFrame = {
      width: input._get("width").cast(),
      height: input._get("height").cast(),
      background: input._get("background").cast(),
      objects: Array::makei(items.length(), fn(i) {
        @boundary.decode_drawable(items[i])
      }),
    }
    if self.backend is Gpu(glow) && glow_lost(glow) {
      @core.throwable(fn() { self.use_svg() })
    }
    if self.backend is Gpu(glow) {
      if !paint_layers(
          self.staging,
          frame,
          items,
          self.layers,
          glow,
          signal,
          videos,
        ) {
        @core.throwable(fn() { self.use_svg() })
      }
    }
    if self.backend is Svg {
      if videos is Some(_) {
        // Context loss and raster budget fallback still produce the same portable SVG.
        self.videos.prepare(input, signal).wait()
        image_check_abort(signal)
        frame = {
          ..frame,
          objects: Array::makei(items.length(), fn(i) {
            @boundary.decode_drawable(items[i])
          }),
        }
      }
      let svg = @core.throwable(fn() {
        @render.frame_to_svg(
          frame,
          "painter-frame",
          true,
          self.layers.resources,
        )
      })
      draw_svg_frame(
        svg,
        self.staging.context.as_any(),
        self.staging.canvas._get("width").cast(),
        self.staging.canvas._get("height").cast(),
        frame.width,
        frame.height,
        frame.background,
        signal,
      ).wait()
    }
    image_check_abort(signal)
    @core.throwable(fn() {
      commit_frame(self.target.context, self.staging.canvas)
    })
  } catch {
    error => raise normalize_image_failure(error, signal)
  }
}

///|
extern "js" fn define_getter(
  object : @core.Any,
  name : String,
  get : () -> @core.Any,
) -> Unit =
  #|(object, name, get) => { Object.defineProperty(object, name, {get, enumerable: true}); }

///|
pub fn create_frame_painter(
  canvas : @core.Any,
  resources : @core.Any,
) -> @core.Promise[@core.Any] {
  @core.from_async(fn() raise {
    let target = @core.throwable(fn() { opaque_surface(canvas) })
    let staging_canvas = @core.throwable(native_canvas)
    errdefer release_canvas(staging_canvas)
    let staging = @core.throwable(fn() { opaque_surface(staging_canvas) })
    let videos = @core.throwable(@browser_media.VideoFrames::new)
    errdefer videos.dispose()
    let lifetime = @core.throwable(fn() {
      @core.new(@core.global_this()._get("AbortController"), [])
    })
    let glow = @core.throwable(fn() { create_glow_renderer() })
    let painter : FramePainter = {
      target,
      staging,
      videos,
      lifetime,
      layers: new_raster_cache(resources),
      backend: if @core.is_nullish(glow) {
        Svg
      } else {
        Gpu(glow)
      },
    }
    let result = @core.from_entries([
      (
        "render",
        @core.any(fn(input : @core.Any, options : @core.Any) {
          @core.from_async(async fn() { painter.render(input, options) })
          |> host_errors
        }),
      ),
      ("dispose", @core.any(fn() { painter.dispose() })),
    ])
    define_getter(result, "backend", fn() {
      @core.any(
        match painter.backend {
          Gpu(glow) if !glow_lost(glow) => "webgl2"
          _ => "canvas2d"
        },
      )
    })
    result
  })
  |> host_errors
}

///|
pub fn draw_svg_frame(
  svg : String,
  value : @core.Any,
  width : Double,
  height : Double,
  scene_width : Double,
  scene_height : Double,
  background : String,
  signal : @core.Any,
) -> @core.Promise[Unit] {
  with_svg_image(svg, signal, fn(image) {
    let context : @canvas.CanvasRenderingContext2D = value.cast()
    let scale = (width / scene_width).min(height / scene_height)
    let draw_width = scene_width * scale
    let draw_height = scene_height * scale
    context.fillStyle = "#000000"
    context.fillRect(0.0, 0.0, width, height)
    context.fillStyle = background
    context.fillRect(0.0, 0.0, width, height)
    context.drawImageScaled(
      image,
      (width - draw_width) / 2.0,
      (height - draw_height) / 2.0,
      draw_width,
      draw_height,
    )
    @core.undefined()
  }).then(fn(_) { @core.Promise::resolve(()) })
}
