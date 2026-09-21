///|
priv struct AudioClip {
  name : String
  source : String
  timing : @audio.Clip
}

///|
async fn mix_audio(
  clips : Array[AudioClip],
  source : @media.AudioSource,
  encoder : @media.Encoder,
  start_frame : Int,
  frames : Int,
) -> Unit {
  let left : FixedArray[Float] = FixedArray::make(frames, 0.0)
  let right : FixedArray[Float] = FixedArray::make(frames, 0.0)
  let time = start_frame.to_double() / @audio.sample_rate.to_double()
  for clip in clips {
    if @audio.window(clip.timing, time, frames) is Some(window) {
      let packets = (source.read)(
        clip.source,
        window.asset_start,
        window.asset_end,
      )
      for packet in packets {
        @audio.mix_stereo(
          window,
          packet.timestamp,
          packet.duration(),
          packet.sample_rate.to_double(),
          packet.left,
          packet.right,
          left,
          right,
        )
      }
    }
  }
  @audio.clamp(left)
  @audio.clamp(right)
  (encoder.add_audio)(@media.StereoPcm(left, right, @audio.sample_rate, time))
}
