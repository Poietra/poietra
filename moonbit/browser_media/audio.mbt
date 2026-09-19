///|
priv struct AudioClip {
  name : String
  source : String
  timing : @audio.Clip
}

///|
priv struct AudioInput {
  owner : InputOwner
  track : @core.Any
}

///|
priv struct AudioPacket {
  timestamp : Double
  duration : Double
  rate : Double
  left : FixedArray[Float]
  right : FixedArray[Float]
}

///|
priv enum PacketState {
  NeedPacket
  Current(AudioPacket)
  Ended
}

///|
priv struct AudioDecoder {
  clip : AudioClip
  sink : @core.Any
  mut iterator : @core.Any?
  mut packet : PacketState
}

///|
pub struct AudioMixer {
  priv clips : Array[AudioClip]
  priv lifetime : @core.Any
  priv signal : @core.Any
  priv inputs : @collection.JsMap[String, AudioInput]
  priv decoders : Array[AudioDecoder]
  priv mut opening : InputOwner?
  priv mut prepared : @core.Promise[Unit]?
  priv mut queue : @core.Promise[Unit]
  priv mut last_end : Double?
  priv mut on_abort : (() -> Unit)?
}

///|
pub fn audible_tracks(value : @core.Any) -> FixedArray[@core.Any] {
  let tracks = []
  if !@core.is_nullish(value) {
    for key in @core.object_keys(value) {
      let track = value._get(key)
      let muted : Bool = track._get("muted").cast()
      let volume : Double = track._get("volume").cast()
      let duration : Double = track._get("duration").cast()
      if !muted && volume > 0.0 && duration > 0.0 {
        tracks.push(track)
      }
    }
  }
  FixedArray::from_array(tracks[:])
}

///|
fn decode_audio_clip(track : @core.Any) -> AudioClip {
  {
    name: track._get("name").cast(),
    source: track._get("asset")._get("src").cast(),
    timing: {
      start: track._get("start").cast(),
      offset: track._get("offset").cast(),
      duration: track._get("duration").cast(),
      gain: track._get("volume").cast(),
    },
  }
}

///|
pub fn AudioMixer::new(
  tracks : FixedArray[@core.Any],
  signal : @core.Any,
) -> AudioMixer {
  let lifetime = @core.new(@core.global_this()._get("AbortController"), [])
  let signal = join_signal(lifetime._get("signal"), signal)
  let mixer : AudioMixer = {
    clips: Array::makei(tracks.length(), fn(i) { decode_audio_clip(tracks[i]) }),
    lifetime,
    signal,
    inputs: @collection.JsMap::new(),
    decoders: [],
    opening: None,
    prepared: None,
    queue: @core.Promise::resolve(()),
    last_end: None,
    on_abort: None,
  }
  let abort = fn() { mixer.release() }
  mixer.on_abort = Some(abort)
  signal._call("addEventListener", [
    @core.any("abort"),
    @core.any(abort),
    @core.from_entries([("once", @core.any(true))]),
  ])
  |> ignore
  mixer
}

///|
fn AudioMixer::release(self : AudioMixer) -> Unit {
  for decoder in self.decoders {
    if decoder.iterator is Some(iterator) {
      try {
        let pending : @core.Promise[@core.Any] = @core.throwable(fn() {
          iterator._call("return", []).cast()
        })
        pending.catch_(fn(_) { @core.Promise::resolve(@core.undefined()) })
        |> ignore
      } catch {
        _ => ()
      }
    }
    decoder.packet = Ended
  }
  self.decoders.clear()
  if self.opening is Some(owner) {
    owner.dispose()
  }
  self.opening = None
  for input in self.inputs.values().iter() {
    input.owner.dispose()
  }
  self.inputs.clear()
}

///|
async fn AudioMixer::open(self : AudioMixer, clip : AudioClip) -> AudioInput {
  if self.inputs.get(clip.source) is Some(input) {
    return input
  }
  let input = open_media(clip.source, self.signal).wait()
  let owner : InputOwner = { input, alive: true, }
  self.opening = Some(owner)
  defer {
    self.opening = None
  }
  errdefer owner.dispose()
  check_abort(self.signal)
  let pending : @core.Promise[@core.Any] = @core.throwable(fn() {
    input._call("getPrimaryAudioTrack", []).cast()
  })
  let track = pending.wait()
  check_abort(self.signal)
  if @core.is_nullish(track) {
    raise MediaFailure(
      "音声「\{clip.name}」のコーデックを再生できません。",
    )
  }
  let pending : @core.Promise[Bool] = @core.throwable(fn() {
    track._call("canDecode", []).cast()
  })
  if !pending.wait() {
    raise MediaFailure(
      "音声「\{clip.name}」のコーデックを再生できません。",
    )
  }
  check_abort(self.signal)
  let input : AudioInput = { owner, track, }
  self.inputs.set(clip.source, input) |> ignore
  input
}

///|
pub fn AudioMixer::prepare(self : AudioMixer) -> @core.Promise[Unit] {
  if self.prepared is Some(pending) {
    return pending
  }
  let pending = @core.from_async(async fn() {
      @core.Promise::resolve(()).wait()
      errdefer {
        self.release()
        self.prepared = None
      }
      for clip in self.clips {
        check_abort(self.signal)
        let input = self.open(clip)
        let sink = @core.throwable(fn() {
          @core.new(audio_runtime()._get("AudioBufferSink"), [input.track])
        })
        self.decoders.push({ clip, sink, iterator: None, packet: NeedPacket, })
      }
    })
    |> native_errors
  self.prepared = Some(pending)
  pending
}

///|
fn audio_packet(value : @core.Any) -> AudioPacket {
  let buffer = value._get("buffer")
  let channels : Int = buffer._get("numberOfChannels").cast()
  {
    timestamp: value._get("timestamp").cast(),
    duration: value._get("duration").cast(),
    rate: buffer._get("sampleRate").cast(),
    left: buffer._call("getChannelData", [@core.any(0)]).cast(),
    right: buffer
    ._call("getChannelData", [@core.any((channels - 1).min(1))])
    .cast(),
  }
}

///|
async fn AudioMixer::mix_frame(
  self : AudioMixer,
  start : Double,
  frames : Int,
) -> @core.Any {
  self.prepare().wait()
  check_abort(self.signal)
  if self.last_end is Some(end) && start + 0.00000001 < end {
    raise MediaFailure(
      "音声のシークには新しいミキサーが必要です。",
    )
  }
  let output = @core.throwable(fn() {
    @core.new(@core.global_this()._get("AudioBuffer"), [
      @core.from_entries([
        ("numberOfChannels", @core.any(2)),
        ("sampleRate", @core.any(@audio.sample_rate)),
        ("length", @core.any(frames)),
      ]),
    ])
  })
  let left : FixedArray[Float] = @core.throwable(fn() {
    output._call("getChannelData", [@core.any(0)]).cast()
  })
  let right : FixedArray[Float] = @core.throwable(fn() {
    output._call("getChannelData", [@core.any(1)]).cast()
  })
  let end = start + frames.to_double() / @audio.sample_rate.to_double()
  for decoder in self.decoders {
    guard @audio.window(decoder.clip.timing, start, frames) is Some(window) else {
      continue
    }
    let iterator = match decoder.iterator {
      Some(iterator) => iterator
      None => {
        let iterator = @core.throwable(fn() {
          decoder.sink._call("buffers", [
            @core.any(window.asset_start),
            @core.any(
              decoder.clip.timing.offset / 1000.0 +
              decoder.clip.timing.duration / 1000.0,
            ),
          ])
        })
        decoder.iterator = Some(iterator)
        iterator
      }
    }
    while !(decoder.packet is Ended) {
      let sample = match decoder.packet {
        Current(sample) => sample
        NeedPacket => {
          let pending : @core.Promise[@core.Any] = @core.throwable(fn() {
            iterator._call("next", []).cast()
          })
          let next = pending.wait()
          check_abort(self.signal)
          if next._get("done").cast() {
            decoder.packet = Ended
            break
          }
          let sample = @core.throwable(fn() { audio_packet(next._get("value")) })
          decoder.packet = Current(sample)
          sample
        }
        Ended => break
      }
      if sample.timestamp >= window.asset_end - 0.000000001 {
        break
      }
      @audio.mix_stereo(
        window,
        sample.timestamp,
        sample.duration,
        sample.rate,
        sample.left,
        sample.right,
        left,
        right,
      )
      if sample.timestamp + sample.duration >= window.asset_end - 0.000000001 {
        break
      }
      decoder.packet = NeedPacket
    }
  }
  @audio.clamp(left)
  @audio.clamp(right)
  check_abort(self.signal)
  self.last_end = Some(end)
  output
}

///|
pub fn AudioMixer::mix(
  self : AudioMixer,
  start : Double,
  frames : Int,
) -> @core.Promise[@core.Any] {
  let previous = self.queue
  let pending = @core.from_async(async fn() {
      previous.wait() catch {
        _ => ()
      }
      self.mix_frame(start, frames)
    })
    |> native_errors
  self.queue = pending
    .then(fn(_) { @core.Promise::resolve(()) })
    .catch_(fn(_) { @core.Promise::resolve(()) })
  pending
}

///|
pub fn AudioMixer::dispose(self : AudioMixer) -> Unit {
  self.lifetime._call("abort", []) |> ignore
  self.release()
  if self.on_abort is Some(abort) {
    self.signal._call("removeEventListener", [
      @core.any("abort"),
      @core.any(abort),
    ])
    |> ignore
    self.on_abort = None
  }
}

///|
pub fn create_audio_mixer(
  tracks : FixedArray[@core.Any],
  signal : @core.Any,
) -> @core.Any {
  let mixer = AudioMixer::new(tracks, signal)
  @core.from_entries([
    ("prepare", @core.any(fn() { mixer.prepare() })),
    (
      "mix",
      @core.any(fn(start : Double, frames : Int) { mixer.mix(start, frames) }),
    ),
    ("dispose", @core.any(fn() { mixer.dispose() })),
  ])
}
