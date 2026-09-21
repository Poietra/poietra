///|
pub(all) suberror InvalidMedia {
  InvalidFrame(String)
  InvalidAudio(String)
}

///|
/// A tightly packed RGBA8 image. Construction checks dimensions and byte count.
pub struct RgbaFrame {
  width : Int
  height : Int
  pixels : Bytes
}

///|
pub fn RgbaFrame::RgbaFrame(
  width : Int,
  height : Int,
  pixels : Bytes,
) -> RgbaFrame raise InvalidMedia {
  if width <= 0 ||
    height <= 0 ||
    width.to_double() * height.to_double() * 4.0 != pixels.length().to_double() {
    raise InvalidFrame("RGBA dimensions must match the byte count.")
  }
  { width, height, pixels, }
}

///|
/// Planar stereo samples. The owner retains the buffers until the consumer returns.
pub struct StereoPcm {
  left : FixedArray[Float]
  right : FixedArray[Float]
  sample_rate : Int
  timestamp : Double
}

///|
pub fn StereoPcm::StereoPcm(
  left : FixedArray[Float],
  right : FixedArray[Float],
  sample_rate : Int,
  timestamp : Double,
) -> StereoPcm raise InvalidMedia {
  if sample_rate <= 0 ||
    timestamp.is_nan() ||
    timestamp.is_inf() ||
    left.length() == 0 ||
    left.length() != right.length() {
    raise InvalidAudio(
      "PCM requires equal nonempty channels, a positive sample rate and finite time.",
    )
  }
  { left, right, sample_rate, timestamp, }
}

///|
pub fn StereoPcm::duration(self : StereoPcm) -> Double {
  self.left.length().to_double() / self.sample_rate.to_double()
}

///|
pub(all) struct VideoSpec {
  width : Int
  height : Int
  fps : Double
  duration_ms : Double
  audio : Bool
}

///|
/// Each callback completes before its input buffers may be reused (backpressure).
pub(all) struct Encoder {
  add_video : async (RgbaFrame) -> Unit
  add_audio : async (StereoPcm) -> Unit
  finish : async () -> Bytes
  dispose : async () -> Unit
}

///|
pub(all) struct AudioSource {
  read : async (String, Double, Double) -> Array[StereoPcm]
}

///|
pub(all) struct Rasterizer {
  rgba : async (String, Int, Int) -> RgbaFrame
  png : async (String) -> Bytes
  svg : async (String) -> Bytes
}

///|
/// The factory owns partial construction. Once acquired, this function owns disposal.
/// Preserve the original failure if cleanup also fails.
pub async fn[T] with_encoder(
  factory : async () -> Encoder,
  consume : async (Encoder) -> T,
) -> T {
  let encoder = factory()
  let value = {
    errdefer ((encoder.dispose)() catch { _ => () })
    consume(encoder)
  }
  (encoder.dispose)()
  value
}
