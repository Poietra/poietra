///|
pub(all) enum TimingEdge {
  MoveTiming
  TrimStart
  TrimEnd
}

///|
pub fn media_gesture(
  before : @scene.MediaPlayback,
  edge : TimingEdge,
  delta : Double,
  source_duration : Double,
) -> @scene.MediaPlayback {
  match edge {
    TrimStart => {
      let minimum = @scene.minimum(10.0, before.duration)
      let change = @scene.clamp(
        delta,
        -@scene.minimum(before.start, before.offset),
        before.duration - minimum,
      )
      {
        start: before.start + change,
        offset: before.offset + change,
        duration: before.duration - change,
      }
    }
    TrimEnd => {
      let available = @scene.maximum(0.0, source_duration - before.offset)
      {
        ..before,
        duration: @scene.clamp(
          before.duration + delta,
          @scene.minimum(10.0, available),
          available,
        ),
      }
    }
    MoveTiming =>
      { ..before, start: @scene.clamp(before.start + delta, 0.0, 600000.0), }
  }
}

///|
pub fn animation_gesture(
  start : Double,
  duration : Double,
  total : Double,
  edge : TimingEdge,
  delta : Double,
) -> (Double, Double) {
  match edge {
    TrimStart => {
      let end = @scene.clamp(start + duration, 0.0, total)
      let start = @scene.clamp(start + delta, 0.0, end)
      (start, end - start)
    }
    TrimEnd =>
      (
        start,
        @scene.clamp(duration + delta, 0.0, @scene.maximum(0.0, total - start)),
      )
    MoveTiming =>
      (
        @scene.clamp(start + delta, 0.0, @scene.maximum(0.0, total - duration)),
        duration,
      )
  }
}
