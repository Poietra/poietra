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
priv struct StudioPositionView {
  source : StudioPosition
  time : Double
}

///|
// The generic binding wraps the initial value in another Option. Pass the
// nullable native default directly so a component outside the provider sees None.
#module("react")
extern "js" fn create_position_context(
  initial : StudioPositionView?,
) -> @react.Context[StudioPositionView?] = "createContext"

///|
let studio_position_context : @react.Context[StudioPositionView?] = create_position_context(
  None,
)

///|
/// One React state update distributes a consistent clock snapshot to its own
/// consumers. Clock ticks can yield to input; document subscriptions stay sync.
fn studio_position_provider(input : @core.Any) -> @react.Element {
  let position : StudioPosition = input._get("position").cast()
  let (time, publish) = @react.use_state_lazy(fn() { position.time })
  @react.use_layout_effect(
    fn() {
      let listener = fn() { publish(position.time) }
      position.listeners.add(listener) |> ignore
      listener()
      fn() { position.listeners.delete(listener) |> ignore }
    },
    [@core.any(position)],
  )
  let view = @react.use_memo(fn() { { source: position, time, } }, [
    @core.any(position),
    @core.any(time),
  ])
  @react.provider(studio_position_context, [children(input)], value=Some(view))
}

///|
fn use_studio_position(position : StudioPosition) -> Double {
  match @react.use_context(studio_position_context) {
    Some(view) if @core.equal(@core.any(view.source), @core.any(position)) =>
      view.time
    _ => position.time
  }
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
