///|
priv enum ClipKind {
  AudioClip
  VideoClip
}

///|
priv struct MediaClip {
  id : String
  name : String
  kind : ClipKind
  asset : @core.Any
  timing : @scene.MediaPlayback
  locked : Bool
  audio : @core.Any?
}

///|
fn playback_value(value : @scene.MediaPlayback) -> @core.Any {
  host_record({
    "start": @core.any(value.start),
    "offset": @core.any(value.offset),
    "duration": @core.any(value.duration),
  })
}

///|
fn media_timing(value : @core.Any) -> @scene.MediaPlayback {
  {
    start: value._get("start").cast(),
    offset: value._get("offset").cast(),
    duration: value._get("duration").cast(),
  }
}

///|
fn media_clip(scene : @core.Any, id : String, kind : ClipKind) -> MediaClip? {
  let source = scene._get(
    if kind is AudioClip {
      "audioTracks"
    } else {
      "objects"
    },
  )
  if !truthy(source) {
    return None
  }
  let object = source._get(id)
  if !truthy(object) {
    return None
  }
  let asset = object._get(if kind is AudioClip { "asset" } else { "media" })
  if !truthy(asset) {
    return None
  }
  let timing = if kind is AudioClip {
    media_timing(object)
  } else if truthy(object._get("playback")) {
    media_timing(object._get("playback"))
  } else {
    { start: 0.0, offset: 0.0, duration: asset._get("duration").cast(), }
  }
  Some({
    id,
    name: object._get("name").cast(),
    kind,
    asset,
    timing,
    locked: kind is VideoClip && truthy(object._get("locked")),
    audio: if kind is AudioClip {
      Some(object)
    } else {
      None
    },
  })
}

///|
fn media_clips(scene : @core.Any) -> Array[MediaClip] {
  let result : Array[MediaClip] = []
  let objects = scene._get("objects")
  for id in @core.object_keys(objects) {
    let object = objects._get(id)
    if object._get("kind").cast() == "video" &&
      media_clip(scene, id, VideoClip) is Some(clip) {
      result.push(clip)
    }
  }
  let audio = scene._get("audioTracks")
  if truthy(audio) {
    for id in @core.object_keys(audio) {
      if media_clip(scene, id, AudioClip) is Some(clip) {
        result.push(clip)
      }
    }
  }
  result
}

///|
fn media_seconds(value : Double) -> String {
  fixed_number(value / 1000.0, 2) + " s"
}

///|
fn media_waveform(
  asset : @core.Any,
  timing : @scene.MediaPlayback,
) -> @react.Element {
  let peaks = asset._get("waveform")
  if !truthy(peaks) || peaks._get("length").cast() == 0 {
    return h("span", { "className": @core.any("waveform-unavailable") }, [
      "波形なし",
    ])
  }
  let peaks : FixedArray[Double] = peaks.cast()
  let duration : Double = asset._get("duration").cast()
  let start = (timing.offset / duration * peaks.length().to_double())
    .floor()
    .to_int()
    .max(0)
    .min(peaks.length())
  let end = (timing.offset + timing.duration) /
    duration *
    peaks.length().to_double()
  let end = end.ceil().to_int().max(start + 1).min(peaks.length())
  let lines : Array[&@react.ReactNode] = []
  for index = start; index < end; index = index + 1 {
    let x = (index - start) * 3 + 1
    let value = @scene.maximum(0.6, peaks[index] * 14.0)
    lines.push(
      h(
        "line",
        {
          "key": @core.any(index - start),
          "x1": @core.any(x),
          "x2": @core.any(x),
          "y1": @core.any(15.0 - value),
          "y2": @core.any(15.0 + value),
          "stroke": @core.any("currentColor"),
          "strokeWidth": @core.any("1.5"),
        },
        [],
      ),
    )
  }
  h(
    "svg",
    {
      "className": @core.any("media-waveform"),
      "viewBox": @core.any("0 0 \{(end - start) * 3} 30"),
      "preserveAspectRatio": @core.any("none"),
      "aria-hidden": @core.any("true"),
    },
    lines,
  )
}

///|
fn media_thumbnail(input : @core.Any) -> @react.Element {
  let video = @react.use_ref((None : @core.Any?))
  let offset : Double = input._get("offset").cast()
  @react.use_effect(
    fn() {
      if video.get_current() is Some(element) {
        let ready : Int = element._get("readyState").cast()
        if ready >= 1 {
          element._set("currentTime", @core.any(offset / 1000.0))
        }
      }
      fn() { () }
    },
    [@core.any(offset)],
  )
  h(
    "video",
    {
      "className": @core.any("media-thumbnail"),
      "ref": video.as_any(),
      "src": input._get("src"),
      "muted": @core.any(true),
      "playsInline": @core.any(true),
      "preload": @core.any("metadata"),
      "aria-hidden": @core.any("true"),
      "onLoadedMetadata": @core.any(fn(event : @core.Any) {
        event
        ._get("currentTarget")
        ._set("currentTime", @core.any(offset / 1000.0))
      }),
    },
    [],
  )
}
