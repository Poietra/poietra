///|
priv struct PaintJob {
  frame : @core.Any
  scene : @core.Any
  key : String
  width : Double
  height : Double
  pixel_width : Double
  pixel_height : Double
}

///|
priv enum PaintLifecycle {
  Opening
  Ready(@core.Any)
  Failed
  Closed
}

///|
priv struct CanvasSession {
  output : @core.Any
  display : @core.Any
  target : @core.Any
  renderer : @core.Any
  lifetime : @core.Any
  latest : () -> PaintJob
  publish : (@core.Any) -> Unit
  fail : () -> Unit
  mut state : PaintLifecycle
  mut pending : PaintJob?
  mut busy : Bool
  mut prepared_scene : @core.Any?
}

///|
fn resize_preview(canvas : @core.Any, width : Double, height : Double) -> Unit {
  let old_width : Double = canvas._get("width").cast()
  let old_height : Double = canvas._get("height").cast()
  // Shrink first so an aspect-ratio change cannot allocate the product of both large edges.
  if width < old_width {
    canvas._set("width", @core.any(width))
  }
  if height < old_height {
    canvas._set("height", @core.any(height))
  }
  if width > old_width {
    canvas._set("width", @core.any(width))
  }
  if height > old_height {
    canvas._set("height", @core.any(height))
  }
}

///|
fn CanvasSession::stop(self : CanvasSession, failed : Bool) -> Unit {
  let previous = self.state
  self.state = if failed { Failed } else { Closed }
  self.pending = None
  self.lifetime._call("abort", []) |> ignore
  if previous is Ready(painter) {
    ui_quiet(painter, "dispose")
  }
  resize_preview(self.target, 0.0, 0.0)
  if failed {
    (self.publish)(@core.null())
    (self.fail)()
  }
}

///|
fn CanvasSession::active(self : CanvasSession) -> Bool {
  match self.state {
    Opening | Ready(_) => true
    Failed | Closed => false
  }
}

///|
fn CanvasSession::drain(self : CanvasSession) -> Unit {
  if self.busy {
    return
  }
  guard self.state is Ready(painter) else { return }
  self.busy = true
  @core.from_async(async fn() {
    defer {
      self.busy = false
    }
    try {
      while self.active() {
        guard self.pending is Some(job) else { break }
        self.pending = None
        let mut next = job
        if next.width <= 0.0 || next.height <= 0.0 {
          continue
        }
        let signal = self.lifetime._get("signal")
        if !self.prepared_scene
          .map(fn(scene) { @core.equal(scene, next.scene) })
          .unwrap_or(false) {
          let prepared = @core.throwable(fn() {
            self.renderer._call("prepareScene", [next.scene])
          })
          wait_signal(prepared, signal) |> ignore
          self.prepared_scene = Some(next.scene)
        }
        if !self.active() {
          break
        }
        if self.pending is Some(queued) {
          if !self.prepared_scene
            .map(fn(scene) { @core.equal(scene, queued.scene) })
            .unwrap_or(false) {
            continue
          }
          next = queued
          self.pending = None
        }
        @core.throwable(fn() {
          resize_preview(self.target, next.pixel_width, next.pixel_height)
        })
        ui_call(painter, "render", [
          next.frame,
          @core.from_entries([("signal", signal)]),
        ])
        |> ignore
        let current = (self.latest)()
        if !self.active() ||
          next.key != current.key ||
          next.pixel_width != current.pixel_width ||
          next.pixel_height != current.pixel_height {
          continue
        }
        @core.throwable(fn() {
          resize_preview(self.output, next.pixel_width, next.pixel_height)
          self.display._call("resetTransform", []) |> ignore
          self.display._set("globalCompositeOperation", @core.any("copy"))
          self.display._call("drawImage", [
            self.target,
            @core.any(0),
            @core.any(0),
          ])
          |> ignore
          (self.publish)(
            @core.from_entries([
              ("frame", next.frame),
              ("key", @core.any(next.key)),
              ("width", @core.any(next.width)),
              ("height", @core.any(next.height)),
            ]),
          )
        })
      }
    } catch {
      _ => if self.active() { self.stop(true) }
    }
  })
  |> ignore
}

///|
fn CanvasSession::enqueue(self : CanvasSession, job : PaintJob) -> Unit {
  if self.active() {
    self.pending = Some(job)
    self.drain()
  }
}

///|
fn CanvasSession::initialize(self : CanvasSession, create : @core.Any) -> Unit {
  @core.from_async(async fn() {
    @core.Promise::resolve(()).wait()
    try {
      let value = @core.throwable(fn() { create._invoke([self.target]) })
      let painter = @core.Promise::resolve(value).wait()
      if self.active() {
        self.state = Ready(painter)
        self.drain()
      } else {
        ui_quiet(painter, "dispose")
      }
    } catch {
      _ => if self.active() { self.stop(true) }
    }
  })
  |> ignore
}
