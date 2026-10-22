///|
/// A sound's measured sync point lands on the visual cue. Only the part before
/// Scene time zero is trimmed; shifting the whole sound would lose the sync.
pub fn sound_placement(
  duration : Double,
  cue : Double,
  target : Double,
) -> Result[@scene.MediaPlayback, String] {
  if duration.is_nan() ||
    duration.is_inf() ||
    duration <= 0.0 ||
    duration > 600000.0 ||
    cue.is_nan() ||
    cue.is_inf() ||
    cue < 0.0 ||
    cue > duration ||
    target.is_nan() ||
    target.is_inf() ||
    target < 0.0 ||
    target > 86400000.0 {
    return Err("効果音を配置する時刻が範囲外です。")
  }
  let offset = (cue - target).max(0.0)
  if duration - offset < 10.0 {
    return Err(
      "この位置では効果音が残りません。合わせる位置を後ろへ移してください。",
    )
  }
  Ok({ start: (target - cue).max(0.0), offset, duration: duration - offset, })
}

///|
/// The selected objects' timing includes explicit property overrides. An empty
/// selection uses the whole Transition (or Composition hold).
pub fn sound_cue_range(
  segment : @scene.Segment,
  timings : Array[@scene.Timing],
) -> TimingRange {
  if timings.is_empty() {
    return { start: segment.start, duration: segment.duration, }
  }
  let mut first = segment.duration
  let mut last = 0.0
  for timing in timings {
    first = first.min(@scene.clamp(timing.start, 0.0, segment.duration))
    last = last.max(
      @scene.clamp(timing.start + timing.duration, 0.0, segment.duration),
    )
  }
  { start: segment.start + first, duration: (last - first).max(0.0), }
}
