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
  mut time : Double?
  mut image : String
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
  let sink = @core.throwable(fn() {
    @core.new(media_runtime()._get("CanvasSink"), [
      track,
      @core.from_entries([("poolSize", @core.any(1))]),
    ])
  })
  let entry : VideoEntry = { owner, sink, time: None, image: "", }
  self.inputs.set(source, entry) |> ignore
  entry
}

///|
fn portable_frame(decoded : @core.Any) -> String raise {
  let canvas = @core.throwable(new_canvas)
  defer release_canvas(canvas)
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
    canvas._call("toDataURL", [@core.any("image/png")]).cast()
  })
}

///|
async fn VideoFrames::prepare_frame(
  self : VideoFrames,
  frame : @core.Any,
  signal : @core.Any,
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
          entry.owner.dispose()
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
      entry.owner.dispose()
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
    if entry.time != Some(request.time) {
      let decoded : @core.Promise[@core.Any] = @core.throwable(fn() {
        entry.sink._call("getCanvas", [@core.any(request.time)]).cast()
      })
      let decoded = decoded.wait()
      check_abort(signal)
      if @core.is_nullish(decoded) {
        raise MediaFailure(
          "動画「\{request.name}」のフレームを読み込めませんでした。",
        )
      }
      let image = portable_frame(decoded)
      check_abort(signal)
      entry.image = image
      entry.time = Some(request.time)
    }
    request.target._set("videoFrame", @core.any(entry.image))
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
      self.prepare_frame(frame, signal)
    })
    |> native_errors
  self.queue = task
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
    entry.owner.dispose()
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
