///|
priv struct BlurProgram {
  program : GLProgram
  source : GLUniform
  texel_step : GLUniform
  sigma : GLUniform
  radius : GLUniform
}

///|
priv struct CompositeProgram {
  program : GLProgram
  source : GLUniform
  halo : GLUniform
  strength : GLUniform
}

///|
priv struct GlowResources {
  owned : Array[GraphicsResource]
  source : GLTexture
  horizontal : RenderTarget
  vertical : RenderTarget
  blur : BlurProgram
  composite : CompositeProgram
}

///|
fn glow_resources(gl : GL) -> GlowResources raise {
  let owned = []
  errdefer release_graphics(gl, owned)
  let source = create_texture(gl, owned)
  let horizontal = create_target(gl, owned)
  let vertical = create_target(gl, owned)
  let blur_program = create_program(gl, gaussian_fragment_shader, owned)
  let composite_program = create_program(gl, composite_fragment_shader, owned)
  let blur : BlurProgram = {
    program: blur_program,
    source: gl_uniform(gl, blur_program, "uSource"),
    texel_step: gl_uniform(gl, blur_program, "uTexelStep"),
    sigma: gl_uniform(gl, blur_program, "uSigma"),
    radius: gl_uniform(gl, blur_program, "uRadius"),
  }
  let composite : CompositeProgram = {
    program: composite_program,
    source: gl_uniform(gl, composite_program, "uSource"),
    halo: gl_uniform(gl, composite_program, "uHalo"),
    strength: gl_uniform(gl, composite_program, "uHaloStrength"),
  }
  @core.throwable(fn() { gl_bind_framebuffer(gl, @core.null()) })
  { owned, source, horizontal, vertical, blur, composite, }
}

///|
priv enum GraphicsLifetime {
  Active
  Lost
  Disposed
} derive(Eq)

///|
priv struct GlowRenderer {
  gl : GL
  canvas : @core.Any
  gpu : GlowResources
  limits : @render.GraphicsLimits
  lifetime : Ref[GraphicsLifetime]
  on_lost : (@core.Any) -> Unit
  mut width : Int
  mut height : Int
}

///|
fn graphics_lost(gl : GL, lifetime : Ref[GraphicsLifetime]) -> Bool {
  lifetime.val != Active || gl_lost(gl)
}

///|
fn dispose_context(gl : GL, canvas : @core.Any) -> Unit {
  release_canvas(canvas)
  if !gl_lost(gl) {
    let extension = @core.any(gl)._call("getExtension", [
      @core.any("WEBGL_lose_context"),
    ])
    if !@core.is_nullish(extension) {
      extension._call("loseContext", []) |> ignore
    }
  }
}

///|
fn GlowRenderer::dispose(self : GlowRenderer) -> Unit {
  if self.lifetime.val == Disposed {
    return
  }
  self.lifetime.val = Disposed
  self.canvas._call("removeEventListener", [
    @core.any("webglcontextlost"),
    @core.any(self.on_lost),
  ])
  |> ignore
  release_graphics(self.gl, self.gpu.owned)
  dispose_context(self.gl, self.canvas)
}

///|
fn resize_targets(
  renderer : GlowRenderer,
  plan : @render.GlowPlan,
) -> Unit raise {
  let gl = renderer.gl
  let gpu = renderer.gpu
  @core.throwable(fn() {
    gl_active_texture(gl, 0)
    for texture in [gpu.source, gpu.horizontal.texture, gpu.vertical.texture] {
      gl_bind_texture(gl, texture)
      gl_resize_texture(gl, plan.width, plan.height)
    }
  })
  for target in [gpu.horizontal, gpu.vertical] {
    let complete : Bool = @core.throwable(fn() {
      gl_bind_framebuffer(gl, @core.any(target.framebuffer))
      @core.equal(
        @core.any(gl)._call("checkFramebufferStatus", [
          gl_value(gl, "FRAMEBUFFER"),
        ]),
        gl_value(gl, "FRAMEBUFFER_COMPLETE"),
      )
    })
    if !complete {
      raise FontError("Glow framebuffer is incomplete.")
    }
  }
  @core.throwable(fn() { gl_bind_framebuffer(gl, @core.null()) })
  graphics_check(gl)
}

///|
fn execute_pass(
  gl : GL,
  gpu : GlowResources,
  plan : @render.GlowPlan,
  pass : @render.GlowPass,
) -> Unit {
  match pass {
    Horizontal | Vertical => {
      let program = gpu.blur
      gl_use_program(gl, program.program)
      gl_uniform_i(gl, program.source, 0)
      gl_uniform_f(gl, program.sigma, plan.sigma)
      gl_uniform_i(gl, program.radius, plan.radius)
      gl_active_texture(gl, 0)
      if pass == @render.Horizontal {
        gl_bind_texture(gl, gpu.source)
        gl_bind_framebuffer(gl, @core.any(gpu.horizontal.framebuffer))
        gl_uniform_xy(gl, program.texel_step, 1.0 / plan.width.to_double(), 0.0)
      } else {
        gl_bind_texture(gl, gpu.horizontal.texture)
        gl_bind_framebuffer(gl, @core.any(gpu.vertical.framebuffer))
        gl_uniform_xy(
          gl,
          program.texel_step,
          0.0,
          1.0 / plan.height.to_double(),
        )
      }
      gl_draw(gl)
    }
    Composite(with_glow) => {
      let program = gpu.composite
      gl_bind_framebuffer(gl, @core.null())
      gl_use_program(gl, program.program)
      gl_active_texture(gl, 0)
      gl_bind_texture(gl, gpu.source)
      gl_uniform_i(gl, program.source, 0)
      gl_active_texture(gl, 1)
      gl_bind_texture(
        gl,
        if with_glow {
          gpu.vertical.texture
        } else {
          gpu.source
        },
      )
      gl_uniform_i(gl, program.halo, 1)
      gl_uniform_f(gl, program.strength, if with_glow { 1.0 } else { 0.0 })
      gl_draw(gl)
    }
  }
}

///|
fn GlowRenderer::render(
  self : GlowRenderer,
  source : @core.Any,
  width : Double,
  height : Double,
  sigma : Double,
) -> Unit raise {
  if self.lifetime.val == Disposed {
    raise FontError("Glow renderer has been disposed.")
  }
  if @core.throwable(fn() { graphics_lost(self.gl, self.lifetime) }) {
    raise FontError("WebGL context is lost.")
  }
  let plan = match @render.glow_plan(width, height, sigma, self.limits) {
    Ok(plan) => plan
    Err(InvalidExtent) =>
      raise FontError(
        "The Glow source exceeds WebGL texture or viewport limits.",
      )
    Err(InvalidRadius) =>
      raise FontError(
        "The Glow blur radius is invalid or exceeds WebGL texture limits.",
      )
  }
  let host = @core.any(self.gl)
  if plan.width != self.width || plan.height != self.height {
    @core.throwable(fn() { resize_canvas(self.canvas, plan.width, plan.height) })
    let actual_width : Int = host._get("drawingBufferWidth").cast()
    let actual_height : Int = host._get("drawingBufferHeight").cast()
    if actual_width != plan.width || actual_height != plan.height {
      raise FontError("WebGL cannot allocate the requested Glow output size.")
    }
    resize_targets(self, plan)
    self.width = plan.width
    self.height = plan.height
  }
  @core.throwable(fn() {
    host._call("viewport", [
      @core.any(0),
      @core.any(0),
      @core.any(plan.width),
      @core.any(plan.height),
    ])
    |> ignore
    gl_active_texture(self.gl, 0)
    gl_bind_texture(self.gl, self.gpu.source)
    for parameter in ["UNPACK_FLIP_Y_WEBGL", "UNPACK_PREMULTIPLY_ALPHA_WEBGL"] {
      host._call("pixelStorei", [gl_value(self.gl, parameter), @core.any(true)])
      |> ignore
    }
    gl_upload(self.gl, source)
    for pass in plan.passes {
      execute_pass(self.gl, self.gpu, plan, pass)
    }
    host._call("flush", []) |> ignore
  })
  graphics_check(self.gl)
}

///|
fn initialize_glow(canvas : @core.Any, gl : GL) -> GlowRenderer raise {
  let lifetime = Ref(Active)
  let on_lost = fn(event : @core.Any) {
    event._call("preventDefault", []) |> ignore
    if lifetime.val != Disposed {
      lifetime.val = Lost
    }
  }
  @core.throwable(fn() {
    canvas._call("addEventListener", [
      @core.any("webglcontextlost"),
      @core.any(on_lost),
    ])
  })
  |> ignore
  errdefer {
    lifetime.val = Disposed
    canvas._call("removeEventListener", [
      @core.any("webglcontextlost"),
      @core.any(on_lost),
    ])
    |> ignore
    dispose_context(gl, canvas)
  }
  if @core.throwable(fn() { graphics_lost(gl, lifetime) }) {
    raise FontError("WebGL context is lost.")
  }
  let limits : @render.GraphicsLimits = @core.throwable(fn() {
    let host = @core.any(gl)
    let texture : Int = host
      ._call("getParameter", [gl_value(gl, "MAX_TEXTURE_SIZE")])
      .cast()
    let viewport = host._call("getParameter", [
      gl_value(gl, "MAX_VIEWPORT_DIMS"),
    ])
    {
      texture,
      viewport_width: viewport._get("0").cast(),
      viewport_height: viewport._get("1").cast(),
    }
  })
  let gpu = glow_resources(gl)
  errdefer release_graphics(gl, gpu.owned)
  @core.throwable(fn() {
    for
      setting in [
        "BLEND", "DEPTH_TEST", "STENCIL_TEST", "SCISSOR_TEST", "DITHER",
      ] {
      @core.any(gl)._call("disable", [gl_value(gl, setting)]) |> ignore
    }
  })
  { gl, canvas, gpu, limits, lifetime, on_lost, width: 0, height: 0, }
}

///|
pub fn create_glow_renderer() -> @core.Any {
  if @core.is_undefined(@core.global_this()._get("document")) {
    return @core.null()
  }
  let canvas = native_canvas()
  let gl = @core.throwable(fn() {
    canvas._call("getContext", [
      @core.any("webgl2"),
      @core.from_entries([
        ("alpha", @core.any(true)),
        ("premultipliedAlpha", @core.any(true)),
        ("antialias", @core.any(false)),
        ("depth", @core.any(false)),
        ("stencil", @core.any(false)),
        ("preserveDrawingBuffer", @core.any(true)),
      ]),
    ])
  }) catch {
    _ => @core.null()
  }
  if @core.is_nullish(gl) {
    release_canvas(canvas)
    return @core.null()
  }
  try {
    let renderer = initialize_glow(canvas, gl.cast())
    let result = @core.from_entries([
      ("canvas", canvas),
      (
        "render",
        @core.any(fn(
          source : @core.Any,
          width : Double,
          height : Double,
          sigma : Double,
        ) {
          renderer.render(source, width, height, sigma) catch {
            error => native_throw(host_error(error))
          }
        }),
      ),
      ("dispose", @core.any(fn() { renderer.dispose() })),
    ])
    define_getter(result, "lost", fn() {
      @core.any(graphics_lost(renderer.gl, renderer.lifetime))
    })
    result
  } catch {
    _ => @core.null()
  }
}
