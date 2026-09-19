///|
fn report_import(
  callback : @core.Any,
  phase : @assets.ImportPhase,
  value : Double,
) -> Unit raise {
  if !@core.is_nullish(callback) {
    let phase = match phase {
      Reading => "reading"
      Waveform => "waveform"
      Uploading => "uploading"
      Saving => "saving"
    }
    @core.throwable(fn() {
      callback._call("call", [
        @core.undefined(),
        @core.from_entries([
          ("phase", @core.any(phase)),
          ("progress", @core.any(value)),
        ]),
      ])
    })
    |> ignore
  }
}

///|
fn host_promise(
  value : @core.Any,
  name : String,
  args : FixedArray[@core.Any],
) -> @core.Promise[@core.Any] raise {
  @core.throwable(fn() { @core.Promise::resolve(value._call(name, args)) })
}

///|
async fn close_iterator(iterator : @core.Any) -> Unit {
  try host_promise(iterator, "return", []).wait() |> ignore catch {
    _ => ()
  }
}

///|
async fn import_waveform(
  track : @core.Any,
  seconds : Double,
  signal : @core.Any,
  progress : @core.Any,
) -> FixedArray[Double] {
  report_import(progress, Waveform, 0.0)
  let runtime = audio_runtime().wait()
  check_abort(signal)
  let sink = @core.throwable(fn() {
    @core.new(runtime._get("AudioBufferSink"), [track])
  })
  let times = FixedArray::makei(128, fn(i) { i.to_double() / 128.0 * seconds })
  let iterator = @core.throwable(fn() {
    sink._call("buffersAtTimestamps", [@core.any(times)])
  })
  errdefer close_iterator(iterator)
  let peaks : Array[Double] = []
  while true {
    check_abort(signal)
    let step = host_promise(iterator, "next", []).wait()
    check_abort(signal)
    if step._get("done").cast() {
      break
    }
    let sample = step._get("value")
    let mut peak = 0.0
    if !@core.is_nullish(sample) {
      let buffer = sample._get("buffer")
      let channels : Int = buffer._get("numberOfChannels").cast()
      for channel = 0; channel < channels; channel = channel + 1 {
        let values : FixedArray[Float] = @core.throwable(fn() {
          buffer._call("getChannelData", [@core.any(channel)]).cast()
        })
        for value in values {
          peak = peak.max(value.to_double().abs())
        }
      }
    }
    peaks.push(1.0.min((peak * 1000.0).round() / 1000.0))
    report_import(progress, Waveform, peaks.length().to_double() / 128.0)
  }
  FixedArray::from_array(peaks[:])
}

///|
fn header_bytes(value : @core.Any) -> Bytes {
  let values : FixedArray[Int] = value.cast()
  Bytes::makei(values.length().min(32), fn(i) { values[i].to_byte() })
}

///|
pub fn prepare_media(
  file : @core.Any,
  signal : @core.Any,
  progress : @core.Any,
) -> @core.Promise[@core.Any] {
  @core.from_async(async fn() {
    check_abort(signal)
    let size : Double = file._get("size").cast()
    if size <= 0.0 || size > @assets.media_limit.to_double() {
      raise MediaFailure(
        "音声・動画は 32 MB 以下にしてください。",
      )
    }
    let runtime = media_runtime().wait()
    check_abort(signal)
    let input = @core.throwable(fn() {
      @core.new(runtime._get("Input"), [
        @core.from_entries([
          ("source", @core.new(runtime._get("BlobSource"), [file])),
          ("formats", runtime._get("ALL_FORMATS")),
        ]),
      ])
    })
    let owner : InputOwner = { input, alive: true, }
    defer (@core.throwable(fn() { owner.dispose() }) catch { _ => () })
    let cancel = fn() { owner.dispose() }
    defer signal._call("removeEventListener", [
        @core.any("abort"),
        @core.any(cancel),
      ])
      |> ignore
    @core.throwable(fn() {
      signal._call("addEventListener", [
        @core.any("abort"),
        @core.any(cancel),
        @core.from_entries([("once", @core.any(true))]),
      ])
    })
    |> ignore
    check_abort(signal)
    report_import(progress, Reading, 0.0)
    let found = @core.Promise::all([
      host_promise(input, "getPrimaryVideoTrack", []),
      host_promise(input, "getPrimaryAudioTrack", []),
      host_promise(input, "computeDuration", []),
    ]).wait()
    check_abort(signal)
    let video = found[0]
    let audio = found[1]
    let seconds : Double = found[2].cast()
    let has_video = !@core.is_nullish(video)
    let has_audio = !@core.is_nullish(audio)
    if (!has_video && !has_audio) ||
      !@assets.bounded_number(seconds, 0.0, 600.0) ||
      seconds == 0.0 {
      raise MediaFailure(
        "10 分以内の音声・動画を選択してください。",
      )
    }
    if has_video && !host_promise(video, "canDecode", []).wait().cast() {
      raise MediaFailure(
        "この動画のコーデックを再生できません。対応する MP4 / WebM を選択してください。",
      )
    }
    check_abort(signal)
    if has_audio && !host_promise(audio, "canDecode", []).wait().cast() {
      raise MediaFailure(
        "この音声のコーデックを再生できません。MP3 / WAV などに変換してください。",
      )
    }
    check_abort(signal)
    let width = if has_video {
      host_promise(video, "getDisplayWidth", []).wait()
    } else {
      @core.undefined()
    }
    let height = if has_video {
      host_promise(video, "getDisplayHeight", []).wait()
    } else {
      @core.undefined()
    }
    check_abort(signal)
    if has_video {
      if !@assets.bounded_number(width.cast(), 1.0, 8192.0) ||
        !@assets.bounded_number(height.cast(), 1.0, 8192.0) {
        raise MediaFailure(
          "動画の解像度は 8,192 px 以下にしてください。",
        )
      }
      let sink = @core.throwable(fn() {
        @core.new(runtime._get("CanvasSink"), [
          video,
          @core.from_entries([("width", @core.any(160))]),
        ])
      })
      let first = host_promise(sink, "getCanvas", [@core.any(0)]).wait()
      check_abort(signal)
      if @core.is_nullish(first) {
        raise MediaFailure(
          "動画の最初のフレームを読み取れませんでした。",
        )
      }
    }
    let waveform = if has_audio {
      Some(import_waveform(audio, seconds, signal, progress))
    } else {
      None
    }
    check_abort(signal)
    let kind : @assets.MediaKind = if has_video { Video } else { Audio }
    let kind = match kind {
      Video => "video"
      Audio => "audio"
    }
    let declared : String = file._get("type").cast()
    let declared = if declared.is_empty() {
      @assets.extension_mime(file._get("name").cast())
    } else {
      declared
    }
    let header = @core.throwable(fn() {
      file._call("slice", [@core.any(0), @core.any(32)])
    })
    let buffer = host_promise(header, "arrayBuffer", []).wait()
    check_abort(signal)
    let bytes = @core.throwable(fn() {
      @core.new(@core.global_this()._get("Uint8Array"), [buffer])
    })
    guard @assets.media_mime(header_bytes(bytes)[:], declared) is Some(detected) else {
      raise MediaFailure(
        "対応する MP4・WebM・MP3・WAV・OGG・FLAC・M4A を選択してください。",
      )
    }
    let mime = if detected.has_suffix("/mp4") {
      kind + "/mp4"
    } else if detected.has_suffix("/webm") {
      kind + "/webm"
    } else {
      detected
    }
    let metadata = @core.from_entries([
      ("mime", @core.any(mime)),
      ("duration", @core.any((seconds * 1000.0).round())),
      ("width", width),
      ("height", height),
      ("hasAudio", @core.any(has_audio)),
    ])
    if waveform is Some(values) {
      metadata._set("waveform", @core.any(values))
    }
    let blob = @core.throwable(fn() {
      file._call("slice", [@core.any(0), @core.any(size), @core.any(mime)])
    })
    @core.from_entries([
      ("kind", @core.any(kind)),
      ("blob", blob),
      ("asset", metadata),
    ])
  })
  |> native_errors
}
