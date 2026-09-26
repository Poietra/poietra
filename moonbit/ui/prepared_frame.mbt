///|
priv struct PreparedFrame {
  scope : String
  source : @core.Any
  frame : @core.Any
}

///|
priv struct PreparationFailure {
  scope : String
  source : @core.Any
  message : String
}

///|
priv struct FramePreparation {
  renderer : @core.Any
  scope : String
  lifetime : @core.Any
  publish : (PreparedFrame) -> Unit
  fail : (PreparationFailure?) -> Unit
  mut busy : Bool
  mut pending : @core.Any?
}

///|
fn FramePreparation::enqueue(
  self : FramePreparation,
  source : @core.Any,
) -> Unit {
  self.pending = Some(source)
  if self.busy {
    return
  }
  self.busy = true
  @core.from_async(async fn() {
    defer {
      self.busy = false
    }
    let signal = self.lifetime._get("signal")
    while !ui_aborted(signal) {
      guard self.pending is Some(source) else { break }
      self.pending = None
      try {
        let frame = @core.throwable(fn() { ui_snapshot(source) })
        if truthy(self.renderer._get("prepareFrame")) {
          ui_call(self.renderer, "prepareFrame", [frame, signal]) |> ignore
        }
        if ui_aborted(signal) {
          break
        }
        (self.publish)({ scope: self.scope, source, frame, })
        (self.fail)(None)
      } catch {
        error =>
          if !ui_aborted(signal) {
            (self.fail)(
              Some({
                scope: self.scope,
                source,
                message: error_message(
                  ui_native_error(error),
                  "動画を読み込めませんでした。",
                ),
              }),
            )
          }
      }
    }
  })
  |> ignore
}

///|
priv struct PreparedFrameState {
  frame : @core.Any
  ready : Bool
  pending : Bool
  failure : String?
}

///|
fn use_frame_preparation(
  source : @core.Any,
  renderer : @core.Any,
  scope : String,
  enabled? : Bool = true,
  revision? : @core.Any = @core.undefined(),
) -> PreparedFrameState {
  let (prepared, set_prepared) = @react.use_state((None : PreparedFrame?))
  let (failure, set_failure) = @react.use_state((None : PreparationFailure?))
  let owner = @react.use_ref((None : FramePreparation?))
  let objects : FixedArray[@core.Any] = if @core.is_nullish(source) {
    []
  } else {
    source._get("objects").cast()
  }
  let needs_preparation = enabled &&
    truthy(renderer._get("prepareFrame")) &&
    objects
    .iter()
    .any(fn(item) {
      @core.equal(item._get("object")._get("kind"), @core.any("video")) &&
      !truthy(item._get("videoFrame"))
    })
  @react.use_effect(
    fn() {
      let current : FramePreparation = {
        renderer,
        scope,
        lifetime: new_controller(),
        publish: fn(value) { set_prepared(Some(value)) },
        fail: set_failure,
        busy: false,
        pending: None,
      }
      owner.set_current(Some(current))
      set_prepared(None)
      set_failure(None)
      fn() {
        current.lifetime._call("abort", []) |> ignore
        current.pending = None
        owner.set_current(None)
      }
    },
    [renderer, @core.any(scope), @core.any(enabled), revision],
  )
  @react.use_effect(
    fn() {
      if needs_preparation && owner.get_current() is Some(current) {
        current.enqueue(source)
      }
      fn() { () }
    },
    [source, renderer, @core.any(scope), @core.any(needs_preparation)],
  )
  let frame = @react.use_memo(
    fn() {
      if !needs_preparation {
        return source
      }
      if prepared is Some(value) && value.scope == scope {
        return value.frame
      }
      let result = ui_shallow_copy(source)
      let visible = objects
        .iter()
        .filter(fn(item) {
          !@core.equal(item._get("object")._get("kind"), @core.any("video"))
        })
        .to_array()
      result._set("objects", @core.any(FixedArray::from_array(visible[:])))
      result
    },
    [
      source,
      @core.any(needs_preparation),
      @core.any(prepared),
      @core.any(scope),
    ],
  )
  {
    frame,
    ready: !needs_preparation ||
    prepared.map(fn(value) { value.scope == scope }).unwrap_or(false),
    pending: needs_preparation &&
    !prepared
    .map(fn(value) { @core.equal(value.source, source) })
    .unwrap_or(false),
    failure: match failure {
      Some(value) if value.scope == scope && @core.equal(value.source, source) =>
        Some(value.message)
      _ => None
    },
  }
}

///|
// Preserve the public native hook while editor consumers share a typed result.
pub fn use_prepared_stage_frame(
  source : @core.Any,
  renderer : @core.Any,
  scope : String,
  enabled? : Bool = true,
) -> @core.Any {
  let state = use_frame_preparation(source, renderer, scope, enabled~)
  @core.from_entries([
    ("frame", state.frame),
    ("ready", @core.any(state.ready)),
    ("pending", @core.any(state.pending)),
    ("error", @core.any(state.failure is Some(_))),
  ])
}
