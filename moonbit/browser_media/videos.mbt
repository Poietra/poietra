///|
priv struct InputOwner {
  input : @core.Any
  mut alive : Bool
}

///|
fn InputOwner::dispose(self : InputOwner) -> Unit {
  if !self.alive {
    return
  }
  self.alive = false
  self.input._call("dispose", []) |> ignore
}

///|
priv struct VideoEntry {
  owner : InputOwner
  sink : @core.Any
  mut iterator : @core.Any?
  mut current : @core.Any?
  mut next : @core.Any?
  mut time : Double?
  mut image : String
}

///|
/// Two decoder canvases form a bounded lookahead window. The next timestamp,
/// rather than a nominal frame rate, also covers variable rates and timestamp gaps.
async fn VideoEntry::seek(
  self : VideoEntry,
  time : Double,
  signal : @core.Any,
) -> @core.Any {
  let restart = self.time
    .map(fn(previous) { time < previous || time - previous > 0.25 })
    .unwrap_or(true)
  if restart {
    if self.iterator is Some(iterator) {
      let closed : @core.Promise[@core.Any] = @core.throwable(fn() {
        iterator._call("return", []).cast()
      })
      closed.wait() |> ignore
      check_abort(signal)
    }
    self.iterator = Some(
      @core.throwable(fn() { self.sink._call("canvases", [@core.any(time)]) }),
    )
    self.current = None
    self.next = None
    self.image = ""
    self.next = self.read_next(signal)
  }
  while self.next is Some(next) {
    let timestamp : Double = next._get("timestamp").cast()
    if timestamp > time {
      break
    }
    self.current = Some(next)
    self.image = ""
    self.next = self.read_next(signal)
  }
  self.time = Some(time)
  match self.current {
    Some(current) => current
    None => @core.null()
  }
}

///|
async fn VideoEntry::read_next(
  self : VideoEntry,
  signal : @core.Any,
) -> @core.Any? {
  let iterator = self.iterator.unwrap()
  let result : @core.Promise[@core.Any] = @core.throwable(fn() {
    iterator._call("next", []).cast()
  })
  let result = result.wait()
  check_abort(signal)
  let done : Bool = result._get("done").cast()
  if done {
    None
  } else {
    Some(result._get("value"))
  }
}

///|
fn VideoEntry::dispose(self : VideoEntry) -> Unit {
  self.owner.dispose()
  if self.iterator is Some(iterator) {
    // return() closes the decoder's prefetched samples, including a pending next().
    let closed : @core.Promise[@core.Any] = iterator._call("return", []).cast()
    closed.catch_(fn(_) { @core.Promise::resolve(@core.undefined()) }) |> ignore
  }
  self.iterator = None
  self.current = None
  self.next = None
}

///|
/// Each result owns its canvas. A later seek or another object sharing the same
/// source cannot overwrite a frame while the painter is using it.
pub(all) struct VideoSurface {
  canvas : @core.Any
  timestamp : Double
}

///|
pub struct VideoSurfaces {
  priv entries : Map[String, VideoSurface]
  priv sources : Map[String, Array[VideoSurface]]
}

///|
pub fn VideoSurfaces::get(self : VideoSurfaces, id : String) -> VideoSurface? {
  self.entries.get(id)
}

///|
pub fn VideoSurfaces::dispose(self : VideoSurfaces) -> Unit {
  for _, frames in self.sources {
    for frame in frames {
      release_canvas(frame.canvas)
    }
  }
  self.entries.clear()
  self.sources.clear()
}

///|
priv struct VideoRequest {
  target : @core.Any
  name : String
  source : String?
  time : Double
}

///|
pub struct VideoFrames {
  priv inputs : @collection.JsMap[String, VideoEntry]
  priv lifetime : @core.Any
  priv mut opening : InputOwner?
  priv mut queue : @core.Promise[Unit]
}

///|
pub fn VideoFrames::new() -> VideoFrames {
  {
    inputs: @collection.JsMap::new(),
    lifetime: @core.new(@core.global_this()._get("AbortController"), []),
    opening: None,
    queue: @core.Promise::resolve(()),
  }
}

///|
fn video_requests(frame : @core.Any) -> Array[VideoRequest] {
  let items : FixedArray[@core.Any] = frame._get("objects").cast()
  let requests = []
  for item in items {
    let object = item._get("object")
    let kind : String = object._get("kind").cast()
    let state = item._get("state")
    let visible : Bool = state._get("visible").cast()
    let opacity : Double = state._get("opacity").cast()
    let progress : Double = item._get("writeProgress").cast()
    let video_frame = item._get("videoFrame")
    if kind != "video" ||
      !visible ||
      opacity <= 0.0 ||
      progress <= 0.0 ||
      (
        !@core.is_nullish(video_frame) &&
        !@core.equal(video_frame, @core.any(""))
      ) {
      continue
    }
    let asset = object._get("media")
    let time = item._get("videoTimeMs")
    requests.push({
      target: item,
      name: object._get("name").cast(),
      source: if @core.is_nullish(asset) {
        None
      } else {
        Some(asset._get("src").cast())
      },
      time: if @core.is_nullish(asset) {
        0.0
      } else {
        @assets.video_seconds(
          if @core.is_nullish(time) {
            0.0
          } else {
            time.cast()
          },
          asset._get("duration").cast(),
        )
      },
    })
  }
  requests
}

///|
async fn VideoFrames::open(
  self : VideoFrames,
  source : String,
  name : String,
  signal : @core.Any,
) -> VideoEntry {
  let input = open_media(source, signal).wait()
  let owner : InputOwner = { input, alive: true, }
  self.opening = Some(owner)
  errdefer owner.dispose()
  let cancel = fn() { owner.dispose() }
  defer {
    signal._call("removeEventListener", [@core.any("abort"), @core.any(cancel)])
    |> ignore
    self.opening = None
  }
  @core.throwable(fn() {
    signal._call("addEventListener", [
      @core.any("abort"),
      @core.any(cancel),
      @core.from_entries([("once", @core.any(true))]),
    ])
  })
  |> ignore
  check_abort(signal)
  let track : @core.Promise[@core.Any] = @core.throwable(fn() {
    input._call("getPrimaryVideoTrack", []).cast()
  })
  let track = track.wait()
  check_abort(signal)
  if @core.is_nullish(track) {
    raise MediaFailure(
      "動画「\{name}」のコーデックを再生できません。",
    )
  }
  let can_decode : @core.Promise[Bool] = @core.throwable(fn() {
    track._call("canDecode", []).cast()
  })
  if !can_decode.wait() {
    raise MediaFailure(
      "動画「\{name}」のコーデックを再生できません。",
    )
  }
  check_abort(signal)
  let runtime = media_runtime().wait()
  check_abort(signal)
  let sink = @core.throwable(fn() {
    @core.new(runtime._get("CanvasSink"), [
      track,
      @core.from_entries([("poolSize", @core.any(2))]),
    ])
  })
  let entry : VideoEntry = {
    owner,
    sink,
    iterator: None,
    current: None,
    next: None,
    time: None,
    image: "",
  }
  self.inputs.set(source, entry) |> ignore
  entry
}

///|
fn portable_frame(decoded : @core.Any) -> String raise {
  let canvas = copy_frame(decoded)
  defer release_canvas(canvas)
  @core.throwable(fn() {
    canvas._call("toDataURL", [@core.any("image/png")]).cast()
  })
}

///|
fn copy_frame(decoded : @core.Any) -> @core.Any raise {
  let canvas = @core.throwable(new_canvas)
  errdefer release_canvas(canvas)
  @core.throwable(fn() {
    let source = decoded._get("canvas")
    canvas._set("width", source._get("width"))
    canvas._set("height", source._get("height"))
    let context = canvas._call("getContext", [@core.any("2d")])
    if @core.is_nullish(context) {
      @core.throw_error(
        "動画フレームの Canvas を作成できません。",
      )
    }
    context._call("drawImage", [source, @core.any(0), @core.any(0)]) |> ignore
    canvas
  })
}

///|
async fn VideoFrames::prepare_frame(
  self : VideoFrames,
  frame : @core.Any,
  signal : @core.Any,
  surfaces : VideoSurfaces?,
) -> Unit {
  check_abort(signal)
  let requests = video_requests(frame)
  let sources : @collection.JsMap[String, Unit] = @collection.JsMap::new()
  for request in requests {
    if request.source is Some(source) {
      sources.set(source, ()) |> ignore
    }
  }
  // Release inactive decoders even when the new Scene contains no video at all.
  @core.throwable(fn() {
    for source in self.inputs.keys().iter() {
      if !sources.has(source) {
        if self.inputs.get(source) is Some(entry) {
          entry.dispose()
        }
        self.inputs.delete(source) |> ignore
      }
    }
  })
  for request in requests {
    guard request.source is Some(source) else {
      raise MediaFailure(
        "動画「\{request.name}」の素材がありません。",
      )
    }
    let entry = match self.inputs.get(source) {
      Some(entry) => entry
      None => self.open(source, request.name, signal)
    }
    let cancel = fn() {
      entry.dispose()
      if self.inputs.get(source) is Some(current) &&
        physical_equal(current, entry) {
        self.inputs.delete(source) |> ignore
      }
    }
    @core.throwable(fn() {
      signal._call("addEventListener", [
        @core.any("abort"),
        @core.any(cancel),
        @core.from_entries([("once", @core.any(true))]),
      ])
    })
    |> ignore
    defer signal._call("removeEventListener", [
        @core.any("abort"),
        @core.any(cancel),
      ])
      |> ignore
    check_abort(signal)
    errdefer cancel()
    let decoded = entry.seek(request.time, signal)
    check_abort(signal)
    if @core.is_nullish(decoded) {
      raise MediaFailure(
        "動画「\{request.name}」のフレームを読み込めませんでした。",
      )
    }
    if surfaces is Some(surfaces) {
      let timestamp : Double = decoded._get("timestamp").cast()
      let frames = surfaces.sources.get_or_init(source, fn() { [] })
      let surface = match
        frames.iter().find_first(fn(v) { v.timestamp == timestamp }) {
        Some(surface) => surface
        None => {
          let surface : VideoSurface = {
            canvas: copy_frame(decoded),
            timestamp,
          }
          frames.push(surface)
          surface
        }
      }
      let id : String = request.target._get("object")._get("id").cast()
      surfaces.entries[id] = surface
    } else {
      if entry.image.is_empty() {
        entry.image = portable_frame(decoded)
      }
      request.target._set("videoFrame", @core.any(entry.image))
    }
    check_abort(signal)
  }
}

///|
/// A decoder is never used concurrently. Failed/cancelled requests do not poison
/// the queue, and disposal aborts both active and queued work.
pub fn VideoFrames::prepare(
  self : VideoFrames,
  frame : @core.Any,
  signal : @core.Any,
) -> @core.Promise[Unit] {
  let signal = join_signal(self.lifetime._get("signal"), signal)
  let previous = self.queue
  let task = @core.from_async(async fn() {
      previous.wait() catch {
        _ => ()
      }
      self.prepare_frame(frame, signal, None)
    })
    |> native_errors
  self.queue = task
  task
}

///|
pub fn VideoFrames::prepare_canvas(
  self : VideoFrames,
  frame : @core.Any,
  signal : @core.Any,
) -> @core.Promise[VideoSurfaces] {
  let signal = join_signal(self.lifetime._get("signal"), signal)
  let previous = self.queue
  let task = @core.from_async(async fn() {
      previous.wait() catch {
        _ => ()
      }
      let surfaces : VideoSurfaces = { entries: Map([]), sources: Map([]), }
      errdefer surfaces.dispose()
      self.prepare_frame(frame, signal, Some(surfaces))
      surfaces
    })
    |> native_errors
  self.queue = task.then(fn(_) { @core.Promise::resolve(()) })
  // Consumers observe task; the internal queue must not cause an unhandled rejection.
  self.queue.catch_(fn(_) { @core.Promise::resolve(()) }) |> ignore
  task
}

///|
pub fn VideoFrames::dispose(self : VideoFrames) -> Unit {
  let aborted : Bool = self.lifetime._get("signal")._get("aborted").cast()
  if aborted {
    return
  }
  self.lifetime._call("abort", []) |> ignore
  if self.opening is Some(owner) {
    owner.dispose()
  }
  self.opening = None
  for entry in self.inputs.values().iter() {
    entry.dispose()
  }
  self.inputs.clear()
}

///|
pub fn create_video_frames() -> @core.Any {
  let frames = VideoFrames::new()
  @core.from_entries([
    (
      "prepare",
      @core.any(fn(frame : @core.Any, signal : @core.Any) {
        frames.prepare(frame, signal)
      }),
    ),
    ("dispose", @core.any(fn() { frames.dispose() })),
  ])
}

///|
let svg_videos : Ref[VideoFrames?] = Ref(None)

///|
let svg_queue : Ref[@core.Promise[Unit]] = Ref(@core.Promise::resolve(()))

///|
let svg_idle : Ref[@core.Any] = Ref(@core.undefined())

///|
pub fn prepare_video_frame(
  frame : @core.Any,
  signal : @core.Any,
) -> @core.Promise[Unit] {
  if svg_videos.val is None && video_requests(frame).is_empty() {
    return @core.Promise::resolve(())
  }
  let previous = svg_queue.val
  let task = @core.from_async(async fn() {
      previous.wait() catch {
        _ => ()
      }
      check_abort(signal)
      @core.global_this()._call("clearTimeout", [svg_idle.val]) |> ignore
      let frames = match svg_videos.val {
        Some(frames) => frames
        None => {
          let frames = VideoFrames::new()
          svg_videos.val = Some(frames)
          frames
        }
      }
      defer {
        svg_idle.val = @core.global_this()._call("setTimeout", [
          @core.any(fn() {
            frames.dispose()
            if svg_videos.val is Some(current) &&
              physical_equal(current, frames) {
              svg_videos.val = None
            }
          }),
          @core.any(1000),
        ])
      }
      frames.prepare(frame, signal).wait()
    })
    |> native_errors
  svg_queue.val = task
  task
}
