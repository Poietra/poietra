///|
fn unsupported_reason() -> String? {
  let global = @core.global_this()
  if !@core.is_nullish(global._get("isSecureContext")) &&
    !global._get("isSecureContext").cast() {
    return Some(
      "動画の書き出しには安全な接続が必要です。HTTPS または localhost で開いてください。",
    )
  }
  if ["document", "VideoEncoder", "VideoFrame"].any(fn(key) {
      @core.is_nullish(global._get(key))
    }) {
    return Some(
      "このブラウザは WebCodecs に対応していません。Chrome または Edge で開いてください。",
    )
  }
  None
}

///|
pub fn environment_reason() -> @core.Any {
  match unsupported_reason() {
    Some(reason) => @core.any(reason)
    None => @core.undefined()
  }
}

///|
pub fn bitrate_for(width : Double, height : Double, fps : Double) -> Double {
  @exporting.bitrate(width, height, fps)
}

///|
fn supports(
  codec : String,
  width : Double,
  height : Double,
  bitrate : Double,
) -> @core.Promise[Bool] {
  @core.from_async(async fn() {
    try {
      let runtime = video_probe_runtime().wait()
      let pending : @core.Promise[Bool] = @core.throwable(fn() {
        runtime
        ._call("canEncodeVideo", [
          @core.any(codec),
          @core.from_entries([
            ("width", @core.any(width)),
            ("height", @core.any(height)),
            ("bitrate", @core.any(bitrate)),
            ("latencyMode", @core.any("quality")),
            ("alpha", @core.any("discard")),
          ]),
        ])
        .cast()
      })
      pending.wait()
    } catch {
      _ => false
    }
  })
}

///|
pub fn get_export_capabilities() -> @core.Promise[@core.Any] {
  @core.from_async(async fn() {
    let reason = unsupported_reason()
    if reason is Some(reason) {
      return @core.from_entries([
        ("mp4", @core.any(false)),
        ("webm", @core.any(false)),
        ("reason", @core.any(reason)),
      ])
    }
    let bitrate = @exporting.bitrate(1280.0, 720.0, 30.0)
    let available = @core.Promise::all(
      ["avc", "vp9", "vp8"].map(fn(codec) {
        supports(codec, 1280.0, 720.0, bitrate)
      }),
    ).wait()
    let mp4 = available[0]
    let webm = available[1] || available[2]
    let result = @core.from_entries([
      ("mp4", @core.any(mp4)),
      ("webm", @core.any(webm)),
    ])
    if !mp4 && !webm {
      result._set(
        "reason",
        @core.any(
          "このブラウザでは MP4 / WebM を書き出せません。WebCodecs 対応の Chrome または Edge をお試しください。",
        ),
      )
    }
    result
  })
  |> native_errors
}

///|
async fn find_codec(
  container : @exporting.Container,
  width : Double,
  height : Double,
  bitrate : Double,
  signal : @core.Any,
) -> String? {
  let candidates = match container {
    Mp4 => ["avc"]
    Webm => ["vp9", "vp8"]
  }
  for candidate in candidates {
    let pending : @core.Promise[@core.Any] = supports(
        candidate, width, height, bitrate,
      )
      .to_any()
      .cast()
    if abortable(pending, signal).wait().cast() {
      return Some(candidate)
    }
  }
  None
}

///|
pub fn find_export_codec(
  format : String,
  width : Double,
  height : Double,
  bitrate : Double,
  signal : @core.Any,
) -> @core.Promise[@core.Any] {
  @core.from_async(async fn() {
    match
      find_codec(
        if format == "mp4" {
          Mp4
        } else {
          Webm
        },
        width,
        height,
        bitrate,
        signal,
      ) {
      Some(codec) => @core.any(codec)
      None => @core.undefined()
    }
  })
  |> native_errors
}
