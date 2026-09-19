///|
async fn export_timeline(
  timeline : Timeline,
  settings : @core.Any,
  host : @core.Any,
) -> @core.Any {
  let signal = settings._get("signal")
  let progress = settings._get("onProgress")
  check_signal(signal)
  let plan = match
    @exporting.plan(
      settings._get("format").cast(),
      settings._get("fps").cast(),
      timeline.size,
      optional_double(settings._get("width")),
      optional_double(settings._get("height")),
      timeline.segments.map(fn(segment) { segment.duration }),
    ) {
    Ok(plan) => plan
    Err(message) => raise Invalid(message)
  }
  if unsupported_reason() is Some(reason) {
    raise Invalid(reason)
  }
  let resources : Resources = {
    canvas: None,
    painter: None,
    video: None,
    audio: None,
    mixer: None,
    output: None,
  }
  // One owner spans every await, including partially initialized encoders.
  defer resources.release()
  let mut stage = Preparation
  try {
    report(progress, 0.0)
    check_signal(signal)
    let codec = find_codec(
      plan.container,
      plan.width.to_double(),
      plan.height.to_double(),
      plan.bitrate,
      signal,
    )
    check_signal(signal)
    guard codec is Some(codec) else {
      raise Invalid(
        "\{plan.container.label()} を \{plan.width} × \{plan.height} で書き出せません。解像度を下げるか、別の形式をお試しください。",
      )
    }
    if !timeline.audio.is_empty() {
      stage = AudioPreparation
      let audio_codec = match plan.container {
        Mp4 => "aac"
        Webm => "opus"
      }
      let runtime = abortable(audio_encoder_runtime(), signal).wait()
      let pending : @core.Promise[@core.Any] = @core.throwable(fn() {
        runtime
        ._call("canEncodeAudio", [
          @core.any(audio_codec),
          @core.from_entries([
            ("numberOfChannels", @core.any(2)),
            ("sampleRate", @core.any(@audio.sample_rate)),
            ("bitrate", @core.any(128000)),
          ]),
        ])
        .cast()
      })
      if !abortable(pending, signal).wait().cast() {
        raise Invalid(
          "\{plan.container.label()} の音声をエンコードできません。別の形式か、音声エンコード対応のブラウザを使用してください。",
        )
      }
      let mixer = @browser_media.AudioMixer::new(timeline.audio, signal)
      resources.mixer = Some(mixer)
      mixer.prepare().wait()
      resources.audio = Some(
        @core.throwable(fn() {
          @core.new(runtime._get("AudioBufferSource"), [
            @core.from_entries([
              ("codec", @core.any(audio_codec)),
              ("bitrate", @core.any(128000)),
            ]),
          ])
        }),
      )
    }
    stage = ScenePreparation
    timeline.prepare(host, signal)
    check_signal(signal)
    let canvas = @core.throwable(fn() {
      @core.global_this()
      ._get("document")
      ._call("createElement", [@core.any("canvas")])
    })
    resources.canvas = Some(canvas)
    @core.throwable(fn() {
      canvas._set("width", @core.any(plan.width))
      canvas._set("height", @core.any(plan.height))
    })
    stage = PainterPreparation
    // Acquire ownership before honoring cancellation; the initialized painter is released.
    let painter = invoke(host, "createFramePainter", [canvas])
    resources.painter = Some(painter)
    check_signal(signal)
    let runtime = abortable(encoder_runtime(), signal).wait()
    let target = @core.throwable(fn() {
      @core.new(runtime._get("BufferTarget"), [])
    })
    let output = @core.throwable(fn() {
      let format = match plan.container {
        Mp4 =>
          @core.new(runtime._get("Mp4OutputFormat"), [
            @core.from_entries([("fastStart", @core.any("in-memory"))]),
          ])
        Webm => @core.new(runtime._get("WebMOutputFormat"), [])
      }
      @core.new(runtime._get("Output"), [
        @core.from_entries([("format", format), ("target", target)]),
      ])
    })
    let output_owner : OutputOwner = { value: output, phase: Pending, }
    resources.output = Some(output_owner)
    let full_codec = Ref(codec)
    let video = @core.throwable(fn() {
      @core.new(runtime._get("CanvasSource"), [
        canvas,
        @core.from_entries([
          ("codec", @core.any(codec)),
          ("bitrate", @core.any(plan.bitrate)),
          ("alpha", @core.any("discard")),
          ("latencyMode", @core.any("quality")),
          ("keyFrameInterval", @core.any(2)),
          (
            "onEncoderConfig",
            @core.any(fn(config : @core.Any) {
              full_codec.val = config._get("codec").cast()
            }),
          ),
        ]),
      ])
    })
    resources.video = Some(video)
    @core.throwable(fn() {
      let track_options = match plan.container {
        Mp4 => @core.from_entries([])
        Webm => @core.from_entries([("frameRate", @core.any(plan.fps))])
      }
      output._call("addVideoTrack", [video, track_options]) |> ignore
      if resources.audio is Some(audio) {
        output._call("addAudioTrack", [audio]) |> ignore
      }
    })
    stage = EncoderStart
    invoke(output, "start", []) |> ignore
    output_owner.phase = Writing
    check_signal(signal)
    let mut audio_frames = 0.0
    let rate = @audio.sample_rate.to_double()
    let total_audio_frames = (plan.duration / 1000.0 * rate + 0.5).floor()
    for index = 0; index < plan.frames; index = index + 1 {
      check_signal(signal)
      let timestamp = plan.timestamp(index)
      if resources.mixer is Some(mixer) && resources.audio is Some(source) {
        while audio_frames <
              total_audio_frames.min(
                ((timestamp + 1.0 / plan.fps) * rate).ceil(),
              ) {
          stage = AudioFrames
          let frames = (rate / 4.0)
            .min(total_audio_frames - audio_frames)
            .to_int()
          let buffer = mixer.mix(audio_frames / rate, frames).wait()
          check_signal(signal)
          invoke(source, "add", [buffer]) |> ignore
          check_signal(signal)
          audio_frames += frames.to_double()
        }
      }
      stage = VideoFrames
      let frame = @core.throwable(fn() { timeline.frame(timestamp * 1000.0) })
      invoke(painter, "render", [
        frame,
        @core.from_entries([("signal", signal)]),
      ])
      |> ignore
      check_signal(signal)
      // Do not race cancel against asynchronous WebCodecs initialization inside add.
      invoke(video, "add", [
        @core.any(timestamp),
        @core.any(plan.frame_duration(index)),
      ])
      |> ignore
      check_signal(signal)
      report(progress, 0.95 * (index + 1).to_double() / plan.frames.to_double())
    }
    check_signal(signal)
    stage = Finalize
    output_owner.phase = Finalizing
    // Finalize flushes and closes codecs. Observe abort only after it settles.
    invoke(output, "finalize", []) |> ignore
    output_owner.phase = Finished
    check_signal(signal)
    let data = target._get("buffer")
    if @core.is_nullish(data) ||
      @core.equal(data._get("byteLength"), @core.any(0)) {
      raise Invalid("動画データが作成されませんでした。")
    }
    let result = @core.throwable(fn() {
      let blob = @core.new(@core.global_this()._get("Blob"), [
        @core.any(([data] : FixedArray[@core.Any])),
        @core.from_entries([("type", @core.any(plan.container.mime()))]),
      ])
      @core.from_entries([
        ("blob", blob),
        ("mimeType", @core.any(plan.container.mime())),
        ("extension", @core.any(plan.container.extension())),
        ("codec", @core.any(full_codec.val)),
        ("width", @core.any(plan.width)),
        ("height", @core.any(plan.height)),
        ("durationMs", @core.any(plan.duration)),
      ])
    })
    report(progress, 1.0)
    check_signal(signal)
    result
  } catch {
    error => raise contextual_error(error, stage, signal)
  }
}
