///|
/// Browser-local time has its own lifetime and subscribers. Advancing it must
/// not publish document, selection, chat or dialog state through React's root.
priv struct StudioPosition {
  mut time : Double
  listeners : @collection.JsSet[() -> Unit]
}

///|
fn StudioPosition::set(self : StudioPosition, time : Double) -> Unit {
  if self.time == time {
    return
  }
  self.time = time
  for listener in self.listeners.values().iter().to_array() {
    listener()
  }
}

///|
fn use_studio_position(position : StudioPosition) -> Double {
  let (subscribe, snapshot) = @react.use_memo(
    fn() {
      (
        fn(listener : () -> Unit) {
          position.listeners.add(listener) |> ignore
          fn() { position.listeners.delete(listener) |> ignore }
        },
        fn() { position.time },
      )
    },
    [@core.any(position)],
  )
  @react.use_sync_external_store(subscribe, snapshot)
}

///|
fn StudioDocument::segment_at(
  self : StudioDocument,
  time : Double,
) -> @core.Any {
  self.segments
  .iter()
  .find_first(fn(segment) {
    let start : Double = segment._get("start").cast()
    let duration : Double = segment._get("duration").cast()
    time < start + duration
  })
  .unwrap_or(
    if self.segments.is_empty() {
      @core.undefined()
    } else {
      self.segments[self.segments.length() - 1]
    },
  )
}

///|
fn StudioDocument::local_time(self : StudioDocument, time : Double) -> Double {
  if truthy(self.transition) {
    @scene.clamp(
      time -
      (if truthy(self.selected) {
        self.selected._get("start").cast()
      } else {
        0.0
      }),
      0.0,
      self.transition._get("duration").cast(),
    )
  } else {
    0.0
  }
}
