///|
pub fn native_error(error : Error) -> @core.Any {
  match error {
    @project_codec.InvalidProjectFile(message)
    | @job.Invalid(message)
    | @media.InvalidFrame(message)
    | @media.InvalidAudio(message) =>
      @core.new(@core.global_this()._get("Error"), [@core.any(message)])
    @core.ThrowError(value) => value
    _ => @core.any(error)
  }
}

///|
fn render_resources(host : NativeHost) -> @render.Resources {
  {
    equation: @math_render.equation,
    measure_text: fn(text, size) {
      @render.text_metrics(
        text,
        size,
        Some(fn(line) {
          let value = host_measure(host, line, size)
          {
            advance: 0.0,
            left: value.left(),
            right: value.right(),
            ascent: value.ascent(),
            descent: value.descent(),
          }
        }),
      )
    },
    image: fn(source) { source },
    font_styles: fn(_) { host_font_styles(host) },
  }
}

///|
async fn create_encoder(
  host : NativeHost,
  spec : @media.VideoSpec,
) -> @media.Encoder {
  let native = @core.throwable(fn() {
    host_create_encoder(
      host,
      spec.width,
      spec.height,
      spec.fps,
      spec.duration_ms,
      spec.audio,
    )
  }).wait()
  // The factory owns construction failures, including a malformed native interface.
  errdefer (@core.throwable(fn() { encoder_dispose(native) }).wait() catch {
    _ => ()
  })
  @core.throwable(fn() { checked_encoder(native) })
  {
    add_video: async fn(frame) {
      @core.throwable(fn() { encoder_video(native, frame.pixels) }).wait()
    },
    add_audio: async fn(block) {
      if block.sample_rate != 48000 {
        raise @job.Invalid("The headless encoder requires 48 kHz PCM.")
      }
      @core.throwable(fn() {
        encoder_audio(native, block.left, block.right, block.timestamp)
      }).wait()
    },
    finish: async fn() {
      @core.throwable(fn() { encoder_finish(native) }).wait()
    },
    dispose: async fn() {
      @core.throwable(fn() { encoder_dispose(native) }).wait()
    },
  }
}

///|
fn backend(host : NativeHost, signal : @core.Any) -> @job.Backend {
  {
    prepare: async fn(preparation) {
      @math_render.prepare_equations(
        FixedArray::from_array(preparation.equations[:]),
        fn() { host_load_math(host) },
      ).wait()
      let texts = preparation.texts.copy()
      for source in preparation.equations {
        if @math_render.equation(source) is None {
          texts.push(source)
        }
      }
      @core.throwable(fn() {
        host_prepare(
          host,
          FixedArray::from_array(texts[:]),
          FixedArray::from_array(preparation.images[:]),
        )
      }).wait()
      render_resources(host)
    },
    rasterizer: {
      rgba: async fn(svg, width, height) {
        let pixels = @core.throwable(fn() { host_rgba(host, svg) }).wait()
        @media.RgbaFrame(width, height, pixels)
      },
      png: async fn(svg) {
        @core.throwable(fn() { host_png(host, svg) }).wait()
      },
      svg: async fn(svg) {
        @core.throwable(fn() { host_svg(host, svg) }).wait()
      },
    },
    audio: {
      read: async fn(source, start, end) {
        let packets = @core.throwable(fn() {
          host_audio(host, source, start, end)
        }).wait()
        let result = []
        for packet in packets {
          result.push(
            @media.StereoPcm(
              packet.left(),
              packet.right(),
              packet.sample_rate(),
              packet.timestamp(),
            ),
          )
        }
        result
      },
    },
    create_encoder: async fn(spec) { create_encoder(host, spec) },
    check_cancelled: fn() raise {
      @core.throwable(fn() { check_signal(signal) })
    },
    progress: async fn(value) {
      @core.throwable(fn() { host_progress(host, value) }).wait()
    },
  }
}

///|
pub fn required_font_faces(
  inter : String,
  css : String,
  files : @core.Any,
  sources : FixedArray[String],
) -> @core.Any {
  let paths : Map[String, String] = Map([])
  for key in @core.object_keys(files) {
    paths[key] = files._get(key).cast()
  }
  let catalog = @render.font_catalog(inter, css, paths)
  let faces = @render.required_faces(catalog, sources.iter().to_array())
  @core.any(
    FixedArray::makei(faces.length(), fn(i) {
      let face = faces[i]
      @core.from_entries([
        ("family", @core.any(face.family)),
        ("url", @core.any(face.url)),
        ("unicodeRange", @core.from_option(face.unicode_range)),
      ])
    }),
  )
}

///|
pub fn capabilities() -> @core.Any {
  @core.json_parse(@api.capabilities().stringify())
}
