///|
#external
priv type GL

///|
#external
priv type GLTexture

///|
#external
priv type GLFramebuffer

///|
#external
priv type GLShader

///|
#external
priv type GLProgram

///|
#external
priv type GLUniform

///|
extern "js" fn gl_lost(gl : GL) -> Bool =
  #|gl => gl.isContextLost()

///|
extern "js" fn gl_delete_texture(gl : GL, texture : GLTexture) -> Unit =
  #|(gl, texture) => gl.deleteTexture(texture)

///|
extern "js" fn gl_delete_framebuffer(
  gl : GL,
  framebuffer : GLFramebuffer,
) -> Unit =
  #|(gl, framebuffer) => gl.deleteFramebuffer(framebuffer)

///|
extern "js" fn gl_delete_shader(gl : GL, shader : GLShader) -> Unit =
  #|(gl, shader) => gl.deleteShader(shader)

///|
extern "js" fn gl_delete_program(gl : GL, program : GLProgram) -> Unit =
  #|(gl, program) => gl.deleteProgram(program)

///|
extern "js" fn gl_bind_texture(gl : GL, texture : GLTexture) -> Unit =
  #|(gl, texture) => gl.bindTexture(gl.TEXTURE_2D, texture)

///|
extern "js" fn gl_use_program(gl : GL, program : GLProgram) -> Unit =
  #|(gl, program) => gl.useProgram(program)

///|
extern "js" fn gl_uniform_i(gl : GL, location : GLUniform, value : Int) -> Unit =
  #|(gl, location, value) => gl.uniform1i(location, value)

///|
extern "js" fn gl_uniform_f(
  gl : GL,
  location : GLUniform,
  value : Double,
) -> Unit =
  #|(gl, location, value) => gl.uniform1f(location, value)

///|
extern "js" fn gl_uniform_xy(
  gl : GL,
  location : GLUniform,
  x : Double,
  y : Double,
) -> Unit =
  #|(gl, location, x, y) => gl.uniform2f(location, x, y)

///|
extern "js" fn gl_active_texture(gl : GL, slot : Int) -> Unit =
  #|(gl, slot) => gl.activeTexture(gl.TEXTURE0 + slot)

///|
extern "js" fn gl_draw(gl : GL) -> Unit =
  #|gl => gl.drawArrays(gl.TRIANGLES, 0, 3)

///|
extern "js" fn gl_bind_framebuffer(gl : GL, framebuffer : @core.Any) -> Unit =
  #|(gl, framebuffer) => gl.bindFramebuffer(gl.FRAMEBUFFER, framebuffer)

///|
extern "js" fn gl_resize_texture(gl : GL, width : Int, height : Int) -> Unit =
  #|(gl, width, height) => gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA8, width, height, 0, gl.RGBA, gl.UNSIGNED_BYTE, null)

///|
extern "js" fn gl_upload(gl : GL, source : @core.Any) -> Unit =
  #|(gl, source) => gl.texSubImage2D(gl.TEXTURE_2D, 0, 0, 0, gl.RGBA, gl.UNSIGNED_BYTE, source)

///|
priv enum GraphicsResource {
  Texture(GLTexture)
  Framebuffer(GLFramebuffer)
  Program(GLProgram)
}

///|
fn release_graphics(gl : GL, resources : Array[GraphicsResource]) -> Unit {
  for resource in resources {
    match resource {
      Texture(texture) => gl_delete_texture(gl, texture)
      Framebuffer(framebuffer) => gl_delete_framebuffer(gl, framebuffer)
      Program(program) => gl_delete_program(gl, program)
    }
  }
  resources.clear()
}

///|
fn gl_value(gl : GL, name : String) -> @core.Any {
  @core.any(gl)._get(name)
}

///|
fn compile_shader(gl : GL, kind : String, source : String) -> GLShader raise {
  let host = @core.any(gl)
  let shader = @core.throwable(fn() {
    host._call("createShader", [gl_value(gl, kind)])
  })
  if @core.is_nullish(shader) {
    raise FontError("Glow shader allocation failed.")
  }
  let shader : GLShader = shader.cast()
  errdefer gl_delete_shader(gl, shader)
  let success : Bool = @core.throwable(fn() {
    host._call("shaderSource", [@core.any(shader), @core.any(source)]) |> ignore
    host._call("compileShader", [@core.any(shader)]) |> ignore
    host
    ._call("getShaderParameter", [
      @core.any(shader),
      gl_value(gl, "COMPILE_STATUS"),
    ])
    .cast()
  })
  if !success {
    let log = @core.throwable(fn() {
      host._call("getShaderInfoLog", [@core.any(shader)])
    })
    let detail : String = if @core.is_nullish(log) {
      "Unknown compilation error"
    } else {
      log.cast()
    }
    raise FontError("Glow shader compilation failed: \{detail}")
  }
  shader
}

///|
fn create_program(
  gl : GL,
  source : String,
  owned : Array[GraphicsResource],
) -> GLProgram raise {
  let vertex = compile_shader(gl, "VERTEX_SHADER", fullscreen_vertex_shader)
  defer gl_delete_shader(gl, vertex)
  let fragment = compile_shader(gl, "FRAGMENT_SHADER", source)
  defer gl_delete_shader(gl, fragment)
  let host = @core.any(gl)
  let program = @core.throwable(fn() { host._call("createProgram", []) })
  if @core.is_nullish(program) {
    raise FontError("Glow program allocation failed.")
  }
  let program : GLProgram = program.cast()
  owned.push(Program(program))
  let linked : Bool = @core.throwable(fn() {
    host._call("attachShader", [@core.any(program), @core.any(vertex)])
    |> ignore
    host._call("attachShader", [@core.any(program), @core.any(fragment)])
    |> ignore
    host._call("linkProgram", [@core.any(program)]) |> ignore
    host
    ._call("getProgramParameter", [
      @core.any(program),
      gl_value(gl, "LINK_STATUS"),
    ])
    .cast()
  })
  if !linked {
    let log = @core.throwable(fn() {
      host._call("getProgramInfoLog", [@core.any(program)])
    })
    let detail : String = if @core.is_nullish(log) {
      "Unknown link error"
    } else {
      log.cast()
    }
    raise FontError("Glow program linking failed: \{detail}")
  }
  @core.throwable(fn() {
    host._call("detachShader", [@core.any(program), @core.any(vertex)])
    |> ignore
    host._call("detachShader", [@core.any(program), @core.any(fragment)])
    |> ignore
  })
  program
}

///|
fn gl_uniform(gl : GL, program : GLProgram, name : String) -> GLUniform raise {
  let location = @core.throwable(fn() {
    @core.any(gl)._call("getUniformLocation", [
      @core.any(program),
      @core.any(name),
    ])
  })
  if @core.is_nullish(location) {
    raise FontError("Glow shader uniform is unavailable: \{name}")
  }
  location.cast()
}

///|
fn create_texture(gl : GL, owned : Array[GraphicsResource]) -> GLTexture raise {
  let host = @core.any(gl)
  let texture = @core.throwable(fn() { host._call("createTexture", []) })
  if @core.is_nullish(texture) {
    raise FontError("Glow texture allocation failed.")
  }
  let texture : GLTexture = texture.cast()
  owned.push(Texture(texture))
  @core.throwable(fn() {
    gl_bind_texture(gl, texture)
    for
      (parameter, value) in [
        ("TEXTURE_MIN_FILTER", "LINEAR"),
        ("TEXTURE_MAG_FILTER", "LINEAR"),
        ("TEXTURE_WRAP_S", "CLAMP_TO_EDGE"),
        ("TEXTURE_WRAP_T", "CLAMP_TO_EDGE"),
      ] {
      host._call("texParameteri", [
        gl_value(gl, "TEXTURE_2D"),
        gl_value(gl, parameter),
        gl_value(gl, value),
      ])
      |> ignore
    }
  })
  texture
}

///|
priv struct RenderTarget {
  texture : GLTexture
  framebuffer : GLFramebuffer
}

///|
fn create_target(
  gl : GL,
  owned : Array[GraphicsResource],
) -> RenderTarget raise {
  let texture = create_texture(gl, owned)
  let host = @core.any(gl)
  let framebuffer = @core.throwable(fn() { host._call("createFramebuffer", []) })
  if @core.is_nullish(framebuffer) {
    raise FontError("Glow framebuffer allocation failed.")
  }
  let framebuffer : GLFramebuffer = framebuffer.cast()
  owned.push(Framebuffer(framebuffer))
  @core.throwable(fn() {
    gl_bind_framebuffer(gl, @core.any(framebuffer))
    host._call("framebufferTexture2D", [
      gl_value(gl, "FRAMEBUFFER"),
      gl_value(gl, "COLOR_ATTACHMENT0"),
      gl_value(gl, "TEXTURE_2D"),
      @core.any(texture),
      @core.any(0),
    ])
    |> ignore
  })
  { texture, framebuffer, }
}

///|
fn graphics_check(gl : GL) -> Unit raise {
  if @core.throwable(fn() { gl_lost(gl) }) {
    raise FontError("WebGL context is lost.")
  }
  let error : Int = @core.throwable(fn() {
    @core.any(gl)._call("getError", []).cast()
  })
  if error != 0 {
    raise FontError("Glow rendering failed with WebGL error \{error}.")
  }
}
