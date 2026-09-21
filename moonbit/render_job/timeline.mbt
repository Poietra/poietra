///|
priv struct Segment {
  scene : @scene.Scene
  start : Double
  duration : Double
  playback : @scene.PreparedScene
}

///|
pub struct Timeline {
  priv name : String
  priv segments : Array[Segment]
  priv bounds : Array[(Double, Double)]
  priv duration : Double
  priv size : @exporting.Size
  priv images : Array[String]
  priv audio : Array[AudioClip]
  priv issues : Array[String]
}

///|
/// The caller keeps the project stable for the lifetime of the prepared timeline.
pub fn prepare(
  project : @scene.Project,
  compare_ids : (String, String) -> Int,
) -> Timeline raise {
  let kernel : @scene.Kernel = {
    track_progress: @motion.track_progress,
    interpolate: @motion.interpolate,
    cubic_bezier: @motion.cubic_bezier,
    cubic_bezier_ease: @motion.cubic_bezier_ease,
    compare_ids,
  }
  let segments : Array[Segment] = []
  let images : Map[String, Unit] = Map([])
  let audio = []
  let issues = []
  let mut start = 0.0
  for id in project.sceneOrder {
    guard project.scenes.get(id) is Some(scene) else { continue }
    let duration = @scene.scene_duration(scene)
    for _, object in scene.objects {
      if object.kind == @scene.Video {
        issues.push(
          "Video decoding is not available: \{object.name} (\{object.id}).",
        )
      }
      if object.image is Some(asset) {
        if asset.src.has_prefix("data:image/png;base64,") ||
          asset.src.has_prefix("data:image/jpeg;base64,") {
          images[asset.src] = ()
        } else {
          issues.push(
            "Embed a PNG or JPEG image in the portable file: \{object.name} (\{object.id}).",
          )
        }
      }
    }
    for _, track in scene.audioTracks.unwrap_or(Map([])) {
      if !track.muted &&
        track.volume > 0.0 &&
        track.duration > 0.0 &&
        track.start < duration {
        audio.push({
          name: track.name,
          source: track.asset.src,
          timing: {
            start: start + track.start,
            offset: track.offset,
            duration: track.duration.min(duration - track.start),
            gain: track.volume,
          },
        })
      }
    }
    segments.push({
      scene,
      start,
      duration,
      playback: @scene.prepare_scene(scene, kernel),
    })
    start += duration
  }
  if segments.is_empty() {
    raise Invalid("The project has no playable Scenes.")
  }
  if audio.length() > 32 {
    issues.push("Headless rendering supports at most 32 audible tracks.")
  }
  let size : @exporting.Size = {
    width: segments[0].scene.width,
    height: segments[0].scene.height,
  }
  let bounds = segments.map(fn(segment) { (segment.start, segment.duration) })
  {
    name: project.name,
    segments,
    bounds,
    size,
    audio,
    issues,
    images: images.keys().to_array(),
    duration: start,
  }
}

///|
fn Timeline::segment(self : Timeline, time : Double) -> Int {
  @scene.project_segment_at(self.bounds, time).unwrap_or(0)
}

///|
fn Timeline::static_key(self : Timeline, time : Double) -> (Int, Int)? {
  let index = self.segment(time)
  let segment = self.segments[index]
  segment.playback
  .static_frame_key((time - segment.start).max(0.0))
  .map(fn(key) { (index, key) })
}

///|
fn Timeline::svg(
  self : Timeline,
  time : Double,
  width : Int,
  height : Int,
  resources : @render.Resources,
) -> String {
  let segment = self.segments[self.segment(time)]
  let frame = segment.playback.evaluate((time - segment.start).max(0.0))
  let view = @render.svg_frame(
    {
      width: frame.width,
      height: frame.height,
      background: frame.background,
      objects: frame.objects.map(fn(item) {
        {
          id: item.object.id,
          kind: item.object.kind,
          state: item.state,
          world: item.world,
          progress: item.writeProgress,
          order: if item.order == "sequential" {
            @render.Sequential
          } else {
            @render.Together
          },
          image: item.object.image.map(fn(asset) { asset.src }),
          video_frame: None,
        }
      }),
    },
    "headless",
    true,
    resources,
  )
  view.to_svg(output_width=width, output_height=height)
}

///|
fn audio_issue(clip : AudioClip) -> String? {
  if clip.source.has_prefix("data:audio/wav;base64,") ||
    clip.source.has_prefix("data:audio/x-wav;base64,") ||
    clip.source.has_prefix("data:audio/wave;base64,") {
    None
  } else {
    Some("Embed PCM WAV audio in the portable file: \{clip.name}.")
  }
}

///|
pub fn Timeline::inspect(self : Timeline) -> Inspection {
  let issues = self.issues.copy()
  for clip in self.audio {
    if audio_issue(clip) is Some(issue) {
      issues.push(issue)
    }
  }
  {
    name: self.name,
    scenes: self.segments.length(),
    duration_ms: self.duration,
    width: self.size.width,
    height: self.size.height,
    audible_tracks: self.audio.length(),
    issues,
  }
}
