///|
pub let sample_rate : Int = 48000

///|
pub(all) struct Clip {
  start : Double
  offset : Double
  duration : Double
  gain : Double
}

///|
pub(all) struct Window {
  clip : Clip
  start : Double
  frames : Int
  asset_start : Double
  asset_end : Double
}

///|
pub fn window(clip : Clip, start : Double, frames : Int) -> Window? {
  let end = start + frames.to_double() / sample_rate.to_double()
  let track_start = clip.start / 1000.0
  let track_end = (clip.start + clip.duration) / 1000.0
  if end <= track_start || start >= track_end {
    return None
  }
  let offset = clip.offset / 1000.0
  Some({
    clip,
    start,
    frames,
    asset_start: start.max(track_start) - track_start + offset,
    asset_end: end.min(track_end) - track_start + offset,
  })
}

///|
/// The browser lends planar Float32 buffers directly. Compute phase once for
/// both channels, using absolute Double time rather than an accumulated cursor.
pub fn mix_stereo(
  window : Window,
  timestamp : Double,
  duration : Double,
  source_rate : Double,
  source_left : FixedArray[Float],
  source_right : FixedArray[Float],
  left : FixedArray[Float],
  right : FixedArray[Float],
) -> Unit {
  let from = window.asset_start.max(timestamp)
  let to = window.asset_end.min(timestamp + duration)
  if to <= from || source_left.is_empty() || source_right.is_empty() {
    return
  }
  let offset = window.clip.offset / 1000.0
  let track_start = window.clip.start / 1000.0
  let rate = sample_rate.to_double()
  let begin = ((from - offset + track_start - window.start) * rate - 0.000001)
    .ceil()
    .max(0.0)
    .to_int()
  let finish = ((to - offset + track_start - window.start) * rate - 0.000001)
    .ceil()
    .min(window.frames.to_double())
    .to_int()
  let last = source_left.length().min(source_right.length()) - 1
  for index = begin; index < finish; index = index + 1 {
    let position = (
        window.start +
        index.to_double() / rate -
        track_start +
        offset -
        timestamp
      ) *
      source_rate
    let a = position.floor().min(last.to_double()).max(0.0).to_int()
    let b = (a + 1).min(last)
    let fraction = (position - a.to_double()).min(1.0).max(0.0)
    let inverse = 1.0 - fraction
    left[index] = Float::from_double(
      left[index].to_double() +
      (
        source_left[a].to_double() * inverse +
        source_left[b].to_double() * fraction
      ) *
      window.clip.gain,
    )
    right[index] = Float::from_double(
      right[index].to_double() +
      (
        source_right[a].to_double() * inverse +
        source_right[b].to_double() * fraction
      ) *
      window.clip.gain,
    )
  }
}

///|
pub fn clamp(samples : FixedArray[Float]) -> Unit {
  for index = 0; index < samples.length(); index = index + 1 {
    let sample = samples[index]
    samples[index] = if sample > 1.0 {
      1.0
    } else if sample < -1.0 {
      -1.0
    } else {
      sample
    }
  }
}
