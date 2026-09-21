///|
fn validate(
  timeline : Timeline,
  request : RenderRequest,
) -> @exporting.Plan raise {
  if !timeline.issues.is_empty() {
    raise Invalid(timeline.issues.join("\n"))
  }
  if request.format == Mp4 {
    for clip in timeline.audio {
      if audio_issue(clip) is Some(issue) {
        raise Invalid(issue)
      }
    }
  }
  let plan = match
    @exporting.plan(
      if request.format == Mp4 {
        "mp4"
      } else {
        "webm"
      },
      request.fps,
      timeline.size,
      request.width,
      request.height,
      [timeline.duration],
    ) {
    Ok(plan) => plan
    Err(message) => raise Invalid(message)
  }
  if plan.width > 1920 ||
    plan.height > 1920 ||
    plan.width * plan.height > max_pixels {
    raise Invalid(
      "Headless output is limited to 1920 pixels per side and 2,073,600 pixels per frame.",
    )
  }
  if request.format == Mp4 &&
    (
      timeline.duration > max_video_duration_ms ||
      plan.frames > max_video_frames
    ) {
    raise Invalid(
      "Headless MP4 output is limited to 60 seconds and 1800 frames.",
    )
  }
  if request.time_ms.is_nan() ||
    request.time_ms.is_inf() ||
    request.time_ms < 0.0 ||
    request.time_ms > timeline.duration {
    raise Invalid("timeMs must lie inside the project timeline.")
  }
  if request.format == Mp4 && request.time_ms != 0.0 {
    raise Invalid("timeMs applies only to SVG/PNG output.")
  }
  plan
}

///|
fn Timeline::preparation(self : Timeline) -> Preparation {
  let texts : Map[String, Unit] = Map([])
  let equations : Map[String, Unit] = Map([])
  for segment in self.segments {
    for _, composition in segment.scene.compositions {
      for id, state in composition.states {
        if segment.scene.objects.get(id) is Some(object) {
          match object.kind {
            Text => texts[state.text] = ()
            Equation => equations[state.text] = ()
            _ => ()
          }
        }
      }
    }
  }
  {
    texts: texts.keys().to_array(),
    equations: equations.keys().to_array(),
    images: self.images,
  }
}

///|
/// Application execution depends only on typed ports; no JS objects or HTTP.
pub async fn render(
  timeline : Timeline,
  request : RenderRequest,
  backend : Backend,
) -> RenderResult {
  (backend.check_cancelled)()
  let plan = validate(timeline, request)
  let resources = (backend.prepare)(timeline.preparation())
  (backend.check_cancelled)()
  let (bytes, frames, rasterized) = match request.format {
    Svg => {
      let svg = timeline.svg(
        request.time_ms,
        plan.width,
        plan.height,
        resources,
      )
      ((backend.rasterizer.svg)(svg), 0, 0)
    }
    Png => {
      let svg = timeline.svg(
        request.time_ms,
        plan.width,
        plan.height,
        resources,
      )
      ((backend.rasterizer.png)(svg), 0, 1)
    }
    Mp4 =>
      @media.with_encoder(
        async fn() {
          (backend.create_encoder)({
            width: plan.width,
            height: plan.height,
            fps: plan.fps,
            duration_ms: timeline.duration,
            audio: !timeline.audio.is_empty(),
          })
        },
        async fn(encoder) {
          let mut previous : (Int, Int)? = None
          let mut pixels : @media.RgbaFrame? = None
          let mut rasterized = 0
          let mut audio_frame = 0
          let total_audio_frames = (timeline.duration /
            1000.0 *
            @audio.sample_rate.to_double())
            .ceil()
            .to_int()
          for index in 0..<plan.frames {
            (backend.check_cancelled)()
            let timestamp = plan.timestamp(index)
            let key = timeline.static_key(timestamp * 1000.0)
            let frame = match pixels {
              Some(frame) if key is Some(_) && key == previous => frame
              _ => {
                let svg = timeline.svg(
                  timestamp * 1000.0,
                  plan.width,
                  plan.height,
                  resources,
                )
                let frame = (backend.rasterizer.rgba)(
                  svg,
                  plan.width,
                  plan.height,
                )
                if frame.width != plan.width || frame.height != plan.height {
                  raise Invalid(
                    "Rasterizer returned unexpected frame dimensions.",
                  )
                }
                rasterized += 1
                pixels = Some(frame)
                frame
              }
            }
            previous = key
            (encoder.add_video)(frame)
            if !timeline.audio.is_empty() {
              let end = ((timestamp + 1.0 / plan.fps) *
                @audio.sample_rate.to_double())
                .ceil()
                .to_int()
                .min(total_audio_frames)
              while audio_frame < end {
                let count = (total_audio_frames - audio_frame).min(
                  @audio.sample_rate / 4,
                )
                mix_audio(
                  timeline.audio,
                  backend.audio,
                  encoder,
                  audio_frame,
                  count,
                )
                audio_frame += count
              }
            }
            (backend.progress)(
              (index + 1).to_double() / plan.frames.to_double() * 0.95,
            )
          }
          (backend.check_cancelled)()
          ((encoder.finish)(), plan.frames, rasterized)
        },
      )
  }
  (backend.check_cancelled)()
  (backend.progress)(1.0)
  {
    bytes,
    format: request.format,
    width: plan.width,
    height: plan.height,
    duration_ms: if request.format == Mp4 {
      timeline.duration
    } else {
      0.0
    },
    frames,
    rasterized_frames: rasterized,
    audio_codec: if request.format == Mp4 && !timeline.audio.is_empty() {
      Some(Mp3)
    } else {
      None
    },
  }
}
