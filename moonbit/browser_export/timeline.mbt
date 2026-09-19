///|
priv struct Segment {
  source : @core.Any
  start : Double
  duration : Double
  playback : @boundary.Playback
}

///|
priv struct Timeline {
  segments : Array[Segment]
  bounds : Array[(Double, Double)]
  size : @exporting.Size
  audio : FixedArray[@core.Any]
}

///|
fn size(value : @core.Any) -> @exporting.Size {
  { width: value._get("width").cast(), height: value._get("height").cast(), }
}

///|
fn Timeline::frame(self : Timeline, time : Double) -> @core.Any {
  let index = @scene.project_segment_at(self.bounds, time).unwrap_or(0)
  let segment = self.segments[index]
  @boundary.playback_frame(segment.playback, (time - segment.start).max(0.0))
}

///|
async fn Timeline::prepare(
  self : Timeline,
  host : @core.Any,
  signal : @core.Any,
) -> Unit {
  for segment in self.segments {
    check_signal(signal)
    let pending : @core.Promise[@core.Any] = @core.throwable(fn() {
      host._call("prepareScene", [segment.source]).cast()
    })
    abortable(pending, signal).wait() |> ignore
  }
}

///|
pub fn export_scene(
  scene : @core.Any,
  kernel : @core.Any,
  options : @core.Any,
  host : @core.Any,
) -> @core.Promise[@core.Any] {
  @core.from_async(async fn() {
    let source = @core.throwable(fn() { snapshot(scene) })
    let duration = @boundary.scene_duration(source)
    let timeline : Timeline = {
      segments: [
        {
          source,
          start: 0.0,
          duration,
          playback: @boundary.prepare_playback(source, kernel),
        },
      ],
      bounds: [(0.0, duration)],
      size: size(source),
      audio: @browser_media.audible_tracks(source._get("audioTracks")),
    }
    export_timeline(timeline, shallow_copy(options), host)
  })
  |> native_errors
}

///|
pub fn export_project(
  project : @core.Any,
  kernel : @core.Any,
  options : @core.Any,
  host : @core.Any,
) -> @core.Promise[@core.Any] {
  @core.from_async(async fn() {
    let source = @core.throwable(fn() { snapshot(project) })
    let settings = shallow_copy(options)
    check_signal(settings._get("signal"))
    let values = @boundary.project_segments(source)
    if values.is_empty() {
      raise Invalid("書き出す Scene がありません。")
    }
    let audio = []
    let segments = []
    for value in values {
      let scene = value._get("scene")
      if !@exporting.valid_size(size(scene)) {
        raise Invalid(
          "Scene の幅と高さを正の数に設定してください。",
        )
      }
      let start : Double = value._get("start").cast()
      let duration : Double = value._get("duration").cast()
      segments.push({
        source: scene,
        start,
        duration,
        playback: @boundary.prepare_playback(scene, kernel),
      })
      for track in @browser_media.audible_tracks(scene._get("audioTracks")) {
        let shifted = shallow_copy(track)
        let original_start : Double = track._get("start").cast()
        shifted._set("start", @core.any(original_start + start))
        audio.push(shifted)
      }
    }
    let timeline : Timeline = {
      segments,
      bounds: segments.map(fn(segment) { (segment.start, segment.duration) }),
      size: size(values[0]._get("scene")),
      audio: FixedArray::from_array(audio[:]),
    }
    export_timeline(timeline, settings, host)
  })
  |> native_errors
}
