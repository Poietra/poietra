///|
priv struct PreviewSegment {
  scene : @core.Any
  start : Double
  duration : Double
}

///|
priv struct PreviewTimeline {
  segments : Array[PreviewSegment]
  bounds : Array[(Double, Double)]
  duration : Double
}

///|
priv struct PlaybackClock {
  time : Double
  position : Double
}

///|
priv struct CanvasPresentation {
  key : String
  width : Double
  height : Double
}

///|
fn preview_timeline(project : @core.Any) -> PreviewTimeline {
  let segments = @boundary.project_segments(project)
    .iter()
    .map(fn(value) {
      PreviewSegment::{
        scene: value._get("scene"),
        start: value._get("start").cast(),
        duration: value._get("duration").cast(),
      }
    })
    .to_array()
  {
    segments,
    bounds: segments.map(fn(value) { (value.start, value.duration) }),
    duration: segments.fold(init=0.0, fn(total, segment) {
      total + segment.duration
    }),
  }
}

///|
fn project_playback(input : @core.Any) -> @react.Element {
  let project = input._get("project")
  let renderer = input._get("renderer")
  let kernel = input._get("kernel")
  let factory = input._get("createFramePainter")
  let (time, set_time) = @react.use_state(0.0)
  let (playing, set_playing) = @react.use_state(false)
  let (prepared, set_prepared) = @react.use_state((None : @core.Any?))
  let (error, set_error) = @react.use_state("")
  let (prepared_frame, set_prepared_frame) = @react.use_state(
    (None : PreparedFrame?),
  )
  let play_request = @react.use_ref(Some(0))
  let (painted, set_painted) = @react.use_state((None : CanvasPresentation?))
  let (size, set_size) = @react.use_state(@exporting.Size::{
    width: 800.0,
    height: 450.0,
  })
  let viewport = @react.use_ref((None : @core.Any?))
  let clock = @react.use_ref(Some(PlaybackClock::{ time: 0.0, position: 0.0, }))
  let timeline = @react.use_memo(fn() { preview_timeline(project) }, [project])
  let current = @scene.project_segment_at(timeline.bounds, time).map(fn(index) {
    timeline.segments[index]
  })
  let scene = current
    .map(fn(segment) { segment.scene })
    .unwrap_or(@core.undefined())
  let first = if timeline.segments.is_empty() {
    None
  } else {
    Some(timeline.segments[0].scene)
  }
  let scene_id = if truthy(scene) {
    scene._get("id")
  } else {
    @core.undefined()
  }
  let scene_time = current
    .map(fn(segment) {
      @scene.clamp(time - segment.start, 0.0, segment.duration)
    })
    .unwrap_or(0.0)
  let program = @react.use_memo(
    fn() {
      if truthy(scene) {
        Some(@boundary.prepare_playback(scene, kernel))
      } else {
        None
      }
    },
    [scene, kernel],
  )
  let frame = @react.use_memo(
    fn() {
      program.map(fn(program) { @boundary.playback_frame(program, scene_time) })
    },
    [@core.any(program), @core.any(scene_time)],
  )
  let media = use_media_playback(
    scene,
    scene_time,
    playing,
    @core.any(fn(failure : @core.Any) {
      set_playing(false)
      set_error(
        error_message(failure, "音声を再生できませんでした。"),
      )
    }),
  )
  let key = "project-preview:" +
    string_value(scene_id) +
    ":" +
    first
    .map(fn(value) {
      string_value(value._get("width")) +
      ":" +
      string_value(value._get("height"))
    })
    .unwrap_or("undefined:undefined")
  let ready = prepared
    .map(fn(value) { @core.equal(value, project) })
    .unwrap_or(false)
  let display_frame = match frame {
    Some(frame) => {
      let objects : FixedArray[@core.Any] = frame._get("objects").cast()
      if objects
        .iter()
        .any(fn(item) {
          @core.equal(item._get("object")._get("kind"), @core.any("video"))
        }) {
        match prepared_frame {
          Some(value) =>
            if value.scope == string_value(scene_id) {
              Some(value.frame)
            } else {
              None
            }
          None => None
        }
      } else {
        Some(frame)
      }
    }
    None => None
  }
  let svg = @react.use_memo(
    fn() {
      if display_frame is Some(frame) && ready {
        renderer
        ._call("frameToSvg", [
          frame,
          @core.from_entries([("idPrefix", @core.any("project-preview"))]),
        ])
        .cast()
      } else {
        ""
      }
    },
    [display_frame.unwrap_or(@core.undefined()), @core.any(ready), renderer],
  )
  let queue = @react.use_ref((None : FramePreparation?))
  @react.use_effect(
    fn() {
      let owner : FramePreparation = {
        renderer,
        scope: string_value(scene_id),
        lifetime: new_controller(),
        publish: fn(value) { set_prepared_frame(Some(value)) },
        fail: fn(failure) {
          if failure is Some(value) {
            set_playing(false)
            set_error(value.message)
          }
        },
        busy: false,
        pending: None,
      }
      queue.set_current(Some(owner))
      set_prepared_frame(None)
      fn() {
        owner.lifetime._call("abort", []) |> ignore
        owner.pending = None
        queue.set_current(None)
      }
    },
    [scene_id, renderer, project],
  )
  @react.use_effect(
    fn() {
      if ready && frame is Some(frame) && queue.get_current() is Some(owner) {
        let objects : FixedArray[@core.Any] = frame._get("objects").cast()
        if !objects
          .iter()
          .any(fn(item) {
            @core.equal(item._get("object")._get("kind"), @core.any("video"))
          }) {
          return fn() { () }
        }
        owner.enqueue(frame)
      }
      fn() { () }
    },
    [@core.any(frame), @core.any(ready), renderer, project],
  )
  @react.use_effect(
    fn() {
      fn() {
        play_request.set_current(Some(play_request.get_current().unwrap() + 1))
      }
    },
    [],
  )
  let canvas_visible = truthy(factory) &&
    ready &&
    painted
    .map(fn(value) {
      value.key == key &&
      value.width == size.width &&
      value.height == size.height
    })
    .unwrap_or(false)
  @react.use_effect(
    fn() {
      guard viewport.get_current() is Some(element) else { return fn() { () } }
      let observer = @core.new(@core.global_this()._get("ResizeObserver"), [
        @core.any(fn(entries : FixedArray[@core.Any]) {
          let rect = entries[0]._get("contentRect")
          set_size({
            width: rect._get("width").cast(),
            height: rect._get("height").cast(),
          })
        }),
      ])
      observer._call("observe", [element]) |> ignore
      fn() { observer._call("disconnect", []) |> ignore }
    },
    [],
  )
  @react.use_effect(
    fn() {
      let active = Ref(true)
      play_request.set_current(Some(play_request.get_current().unwrap() + 1))
      media._call("cancel", []) |> ignore
      set_playing(false)
      set_prepared_frame(None)
      @core.from_async(async fn() {
        try {
          let requests = timeline.segments.map(fn(segment) {
            @core.from_async(async fn() {
              ui_call(renderer, "prepareScene", [segment.scene]) |> ignore
            })
          })
          @core.Promise::all(requests).wait() |> ignore
          if active.val {
            set_prepared(Some(project))
            set_error("")
          }
        } catch {
          failure =>
            if active.val {
              set_playing(false)
              set_error(
                error_message(
                  ui_native_error(failure),
                  "Scene を読み込めませんでした。",
                ),
              )
            }
        }
      })
      |> ignore
      fn() { active.val = false }
    },
    [project, renderer],
  )
  @react.use_effect(
    fn() {
      if time > timeline.duration {
        set_time(timeline.duration)
      }
      if timeline.duration <= 0.0 {
        set_playing(false)
      }
      fn() { () }
    },
    [@core.any(timeline.duration)],
  )
  @react.use_effect(
    fn() {
      if !playing {
        return fn() { () }
      }
      let request = Ref(@core.undefined())
      fn tick(now : Double) -> Unit {
        let anchor = clock.get_current().unwrap()
        let next = timeline.duration.min(anchor.position + now - anchor.time)
        set_time(next)
        if next >= timeline.duration {
          set_playing(false)
        } else {
          request.val = @core.global_this()._call("requestAnimationFrame", [
            @core.any(tick),
          ])
        }
      }
      request.val = @core.global_this()._call("requestAnimationFrame", [
        @core.any(tick),
      ])
      fn() {
        @core.global_this()._call("cancelAnimationFrame", [request.val])
        |> ignore
      }
    },
    [@core.any(playing), @core.any(timeline.duration)],
  )
  let seek = fn(value : Double) {
    play_request.set_current(Some(play_request.get_current().unwrap() + 1))
    media._call("cancel", []) |> ignore
    set_playing(false)
    set_time(@scene.clamp(value, 0.0, timeline.duration))
  }
  let toggle = fn() {
    let request = play_request.get_current().unwrap() + 1
    play_request.set_current(Some(request))
    if playing {
      set_playing(false)
      return
    }
    let position = if time >= timeline.duration { 0.0 } else { time }
    @core.from_async(async fn() {
      try {
        ui_call(media, "unlock", []) |> ignore
        if play_request.get_current() != Some(request) {
          return
        }
        clock.set_current(
          Some({
            time: @core.global_this()
            ._get("performance")
            ._call("now", [])
            .cast(),
            position,
          }),
        )
        set_time(position)
        set_playing(true)
      } catch {
        failure =>
          if play_request.get_current() == Some(request) {
            set_error(
              error_message(
                ui_native_error(failure),
                "音声を再生できませんでした。",
              ),
            )
          }
      }
    })
    |> ignore
  }
  let edit = fn() {
    if !truthy(scene) {
      return
    }
    let parts : FixedArray[@core.Any] = @boundary.scene_segments(scene).cast()
    let mut selected = if parts.is_empty() {
      None
    } else {
      Some(parts[parts.length() - 1])
    }
    for part in parts {
      let start : Double = part._get("start").cast()
      let duration : Double = part._get("duration").cast()
      if scene_time < start + duration {
        selected = Some(part)
        break
      }
    }
    if selected is Some(part) {
      input._get("onOpenChange")._invoke([@core.any(false)]) |> ignore
      input
      ._get("onEdit")
      ._invoke([
        scene_id,
        @core.from_entries([
          ("kind", part._get("kind")),
          ("id", part._get("id")),
        ]),
      ])
      |> ignore
    }
  }
  project_playback_view(
    input,
    {
      timeline,
      scene,
      first,
      frame,
      display_frame,
      key,
      ready,
      canvas_visible,
      size,
      svg,
      time,
      playing,
      error,
    },
    viewport,
    set_painted,
    seek,
    toggle,
    edit,
  )
}
