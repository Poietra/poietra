///|
fn number_option(options : @core.Any, key : String) -> Double? raise {
  let value = options._get(key)
  if @core.is_undefined(value) {
    return None
  }
  if @core.typeof_(value) != "number" {
    raise @job.Invalid("\{key} must be a number.")
  }
  let value : Double = value.cast()
  if value.is_nan() || value.is_inf() {
    raise @job.Invalid("\{key} must be finite.")
  }
  Some(value)
}

///|
fn decode_request(value : @core.Any) -> @job.RenderRequest raise {
  let format = value._get("format")
  let format = if @core.is_undefined(format) {
    @job.Png
  } else {
    if @core.typeof_(format) != "string" {
      raise @job.Invalid("format must be svg, png or mp4.")
    }
    @job.format(format.cast())
  }
  {
    format,
    width: number_option(value, "width"),
    height: number_option(value, "height"),
    fps: number_option(value, "fps").unwrap_or(30.0),
    time_ms: number_option(value, "timeMs").unwrap_or(0.0),
  }
}

///|
fn parse_timeline(text : String) -> @job.Timeline raise {
  if @project_codec.bounded_utf8_size(text, @job.max_input_bytes) >
    @job.max_input_bytes {
    raise @job.Invalid("Headless rendering accepts project files up to 32 MiB.")
  }
  @job.prepare(@project_codec.parse(text), compare_ids)
}

///|
fn encode_result(result : @job.RenderResult) -> @core.Any {
  @core.from_entries([
    ("bytes", @core.any(result.bytes)),
    ("format", @core.any(result.format.name())),
    ("mimeType", @core.any(result.format.mime())),
    ("width", @core.any(result.width)),
    ("height", @core.any(result.height)),
    ("durationMs", @core.any(result.duration_ms)),
    ("frames", @core.any(result.frames)),
    ("rasterizedFrames", @core.any(result.rasterized_frames)),
    (
      "audioCodec",
      match result.audio_codec {
        Some(Mp3) => @core.any("mp3")
        None => @core.null()
      },
    ),
  ])
}

///|
pub fn render_project_file(
  text : String,
  settings : @core.Any,
  host : @core.Any,
) -> @core.Promise[@core.Any] {
  @core.from_async(async fn() {
    @core.throwable(fn() { check_signal(settings._get("signal")) })
    let request = decode_request(settings)
    let timeline = parse_timeline(text)
    let native = @core.throwable(fn() { checked_host(host) })
    encode_result(
      @job.render(timeline, request, backend(native, settings._get("signal"))),
    )
  }).catch_(fn(error) {
    @core.Promise::reject(native_error(error)).to_any().cast()
  })
}

///|
pub fn inspect_project_file(text : String) -> @core.Any {
  try {
    let value = parse_timeline(text).inspect()
    @core.from_entries([
      ("name", @core.any(value.name)),
      ("scenes", @core.any(value.scenes)),
      ("durationMs", @core.any(value.duration_ms)),
      ("width", @core.any(value.width)),
      ("height", @core.any(value.height)),
      ("audibleTracks", @core.any(value.audible_tracks)),
      ("issues", @core.any(FixedArray::from_array(value.issues[:]))),
      ("capabilities", capabilities()),
    ])
  } catch {
    error => {
      native_throw(native_error(error))
      @core.undefined()
    }
  }
}
