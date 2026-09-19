///|
fn finite(value : Double) -> Bool {
  !value.is_nan() && !value.is_inf()
}

///|
pub(all) enum Container {
  Mp4
  Webm
} derive(Eq, Debug)

///|
pub fn Container::extension(self : Container) -> String {
  match self {
    Mp4 => "mp4"
    Webm => "webm"
  }
}

///|
pub fn Container::label(self : Container) -> String {
  match self {
    Mp4 => "MP4"
    Webm => "WebM"
  }
}

///|
pub fn Container::mime(self : Container) -> String {
  "video/" + self.extension()
}

///|
pub(all) struct Size {
  width : Double
  height : Double
}

///|
pub(all) struct Plan {
  container : Container
  width : Int
  height : Int
  fps : Double
  frames : Int
  duration : Double
  bitrate : Double
}

///|
pub fn bitrate(width : Double, height : Double, fps : Double) -> Double {
  ((width * height * fps * 0.16).min(40000000.0).max(1000000.0) + 0.5).floor()
}

///|
pub fn valid_size(size : Size) -> Bool {
  finite(size.width) &&
  finite(size.height) &&
  size.width > 0.0 &&
  size.height > 0.0
}

///|
pub fn plan(
  format : String,
  fps : Double,
  size : Size,
  requested_width : Double?,
  requested_height : Double?,
  durations : Array[Double],
) -> Result[Plan, String] {
  let container = match format {
    "mp4" => Mp4
    "webm" => Webm
    _ =>
      return Err(
        "書き出し形式には MP4 または WebM を選択してください。",
      )
  }
  if fps != 24.0 && fps != 30.0 && fps != 60.0 {
    return Err(
      "フレームレートには 24、30、60 fps のいずれかを選択してください。",
    )
  }
  if !valid_size(size) {
    return Err(
      "Scene の幅と高さを正の数に設定してください。",
    )
  }
  let unit = if container == Mp4 { 2.0 } else { 1.0 }
  let derived = fn(value : Double) {
    ((value / unit + 0.5).floor() * unit).max(unit)
  }
  let width = requested_width.unwrap_or_else(fn() {
    requested_height
    .map(fn(height) { derived(height * size.width / size.height) })
    .unwrap_or(size.width)
  })
  let height = requested_height.unwrap_or_else(fn() {
    requested_width
    .map(fn(width) { derived(width * size.height / size.width) })
    .unwrap_or(size.height)
  })
  if [width, height].any(fn(value) {
      !finite(value) || value <= 0.0 || value > 8192.0 || value.floor() != value
    }) {
    return Err(
      "書き出す幅と高さは 1〜8192 ピクセルの整数にしてください。",
    )
  }
  if container == Mp4 && (width.to_int() % 2 != 0 || height.to_int() % 2 != 0) {
    return Err(
      "MP4 の幅と高さは偶数にしてください。WebM では奇数も使用できます。",
    )
  }
  let duration = durations.fold(init=0.0, fn(total, duration) {
    total + duration
  })
  if !finite(duration) ||
    duration <= 0.0 ||
    durations.any(fn(value) { !finite(value) || value < 0.0 }) {
    return Err(
      "書き出す Scene の再生時間を 0 より大きく設定してください。",
    )
  }
  let frames = (duration * fps / 1000.0).ceil()
  // Check before Int conversion; malformed oversized timelines must not wrap.
  if !finite(frames) || frames > 2147483647.0 {
    return Err(
      "書き出す動画のフレーム数が多すぎます。Scene の再生時間を短くしてください。",
    )
  }
  Ok({
    container,
    width: width.to_int(),
    height: height.to_int(),
    fps,
    frames: frames.to_int(),
    duration: if container == Webm {
      frames / fps * 1000.0
    } else {
      duration
    },
    bitrate: bitrate(width, height, fps),
  })
}

///|
pub fn Plan::timestamp(self : Plan, index : Int) -> Double {
  index.to_double() / self.fps
}

///|
pub fn Plan::frame_duration(self : Plan, index : Int) -> Double {
  (1.0 / self.fps).min(self.duration / 1000.0 - self.timestamp(index))
}
