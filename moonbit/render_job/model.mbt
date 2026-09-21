///|
pub(all) suberror RenderFailure {
  Invalid(String)
}

///|
pub(all) enum Format {
  Svg
  Png
  Mp4
} derive(Eq)

///|
pub fn Format::name(self : Format) -> String {
  match self {
    Svg => "svg"
    Png => "png"
    Mp4 => "mp4"
  }
}

///|
pub fn Format::mime(self : Format) -> String {
  match self {
    Svg => "image/svg+xml"
    Png => "image/png"
    Mp4 => "video/mp4"
  }
}

///|
pub fn format(name : String) -> Format raise RenderFailure {
  match name {
    "svg" => Svg
    "png" => Png
    "mp4" => Mp4
    _ => raise Invalid("format must be svg, png or mp4.")
  }
}

///|
pub(all) struct RenderRequest {
  format : Format
  width : Double?
  height : Double?
  fps : Double
  time_ms : Double
}

///|
pub(all) enum AudioCodec {
  Mp3
} derive(Eq)

///|
pub(all) struct RenderResult {
  bytes : Bytes
  format : Format
  width : Int
  height : Int
  duration_ms : Double
  frames : Int
  rasterized_frames : Int
  audio_codec : AudioCodec?
}

///|
pub(all) struct Preparation {
  texts : Array[String]
  equations : Array[String]
  images : Array[String]
}

///|
pub(all) struct Backend {
  prepare : async (Preparation) -> @render.Resources
  rasterizer : @media.Rasterizer
  audio : @media.AudioSource
  create_encoder : async (@media.VideoSpec) -> @media.Encoder
  check_cancelled : () -> Unit raise
  progress : async (Double) -> Unit
}

///|
pub(all) struct Inspection {
  name : String
  scenes : Int
  duration_ms : Double
  width : Double
  height : Double
  audible_tracks : Int
  issues : Array[String]
}

///|
pub let max_input_bytes : Int = 33554432

///|
pub let max_pixels : Int = 2073600

///|
pub let max_video_duration_ms : Double = 60000.0

///|
pub let max_video_frames : Int = 1800
