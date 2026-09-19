///|
priv struct AudioSignature {
  id : String
  name : String
  source : String
  start : Double
  offset : Double
  duration : Double
  gain : Double
} derive(Eq)

///|
priv struct StableTracks {
  source : @core.Any
  signatures : Array[AudioSignature]
  tracks : FixedArray[@core.Any]
}

///|
fn use_audio_tracks(source : @core.Any) -> FixedArray[@core.Any] {
  let previous = @react.use_ref((None : StableTracks?))
  if previous.get_current() is Some(value) && @core.equal(value.source, source) {
    return value.tracks
  }
  let tracks = @browser_media.audible_tracks(source)
  let signatures = tracks
    .iter()
    .map(fn(track) {
      AudioSignature::{
        id: track._get("id").cast(),
        name: track._get("name").cast(),
        source: track._get("asset")._get("src").cast(),
        start: track._get("start").cast(),
        offset: track._get("offset").cast(),
        duration: track._get("duration").cast(),
        gain: track._get("volume").cast(),
      }
    })
    .to_array()
  let stable = match previous.get_current() {
    Some(value) =>
      if value.signatures == signatures {
        value.tracks
      } else {
        tracks
      }
    None => tracks
  }
  previous.set_current(Some({ source, signatures, tracks: stable, }))
  stable
}

///|
priv struct AudioOwner {
  mut context : @core.Any?
  mut pending : @browser_media.AudioMixer?
  mut generation : Int
}

///|
fn AudioOwner::cancel(self : AudioOwner) -> Unit {
  self.generation += 1
  if self.pending is Some(mixer) {
    self.pending = None
    mixer.dispose()
  }
}

///|
priv enum PumpState {
  Idle
  Mixing
  Stopped
}

///|
priv struct AudioPlayback {
  context : @core.Any
  mixer : @browser_media.AudioMixer
  clock : Double
  position : Double
  nodes : @collection.JsSet[@core.Any]
  report : (@core.Any) -> Unit
  mut next : Double
  mut state : PumpState
  mut timer : @core.Any?
}

///|
fn AudioPlayback::stop(self : AudioPlayback) -> Unit {
  self.state = Stopped
  if self.timer is Some(timer) {
    self.timer = None
    @core.global_this()._call("clearInterval", [timer]) |> ignore
  }
  self.mixer.dispose()
  for node in self.nodes.values().iter() {
    node._set("onended", @core.null())
    ui_quiet(node, "stop")
    ui_quiet(node, "disconnect")
  }
  self.nodes.clear()
}

///|
fn AudioPlayback::pump(self : AudioPlayback) -> Unit {
  guard self.state is Idle else { return }
  self.state = Mixing
  @core.from_async(async fn() {
    defer (if self.state is Mixing { self.state = Idle })
    try {
      while !(self.state is Stopped) {
        let now : Double = self.context._get("currentTime").cast()
        if self.next >= self.position + now - self.clock + 0.6 {
          break
        }
        let buffer = self.mixer.mix(self.next, @audio.sample_rate / 4).wait()
        if self.state is Stopped {
          break
        }
        let at = self.clock + self.next - self.position
        let now : Double = self.context._get("currentTime").cast()
        let skip = (now - at).max(0.0)
        let duration : Double = buffer._get("duration").cast()
        if skip < duration {
          @core.throwable(fn() {
            let node = self.context._call("createBufferSource", [])
            self.nodes.add(node) |> ignore
            node._set("buffer", buffer)
            node._call("connect", [self.context._get("destination")]) |> ignore
            node._set(
              "onended",
              @core.any(fn() {
                self.nodes.delete(node) |> ignore
                node._set("onended", @core.null())
                ui_quiet(node, "disconnect")
              }),
            )
            node._call("start", [@core.any(at.max(now)), @core.any(skip)])
            |> ignore
          })
        }
        self.next += duration
      }
    } catch {
      error =>
        if !(self.state is Stopped) {
          self.stop()
          let value = ui_native_error(error)
          let error = if @core.instanceof_(
              value,
              @core.global_this()._get("Error"),
            ) {
            value
          } else {
            @core.new(@core.global_this()._get("Error"), [
              @core.any(string_value(value)),
            ])
          }
          (self.report)(error)
        }
    }
  })
  |> ignore
}

///|
pub fn use_media_playback(
  scene : @core.Any,
  time : Double,
  playing : Bool,
  on_error : @core.Any,
) -> @core.Any {
  let owner_ref = @react.use_ref((None : AudioOwner?))
  let owner = match owner_ref.get_current() {
    Some(owner) => owner
    None => {
      let owner : AudioOwner = { context: None, pending: None, generation: 0, }
      owner_ref.set_current(Some(owner))
      owner
    }
  }
  let latest = @react.use_ref(Some((time, on_error)))
  latest.set_current(Some((time, on_error)))
  let audio = if @core.is_nullish(scene) {
    @core.undefined()
  } else {
    scene._get("audioTracks")
  }
  let tracks = use_audio_tracks(audio)
  let scene_id = if @core.is_nullish(scene) {
    @core.undefined()
  } else {
    scene._get("id")
  }
  @react.use_effect(
    fn() {
      fn() {
        owner.cancel()
        if owner.context is Some(audio) {
          owner.context = None
          let closing = @core.throwable(fn() { audio._call("close", []) }) catch {
            _ => @core.undefined()
          }
          @core.Promise::resolve(closing).catch_(fn(_) {
            @core.Promise::resolve(@core.undefined())
          })
          |> ignore
        }
      }
    },
    [],
  )
  @react.use_effect(
    fn() {
      if !playing || tracks.is_empty() {
        if owner.pending is Some(mixer) {
          owner.pending = None
          mixer.dispose()
        }
        return fn() { () }
      }
      let report = fn(value : @core.Any) {
        let callback = latest.get_current().unwrap().1
        if truthy(callback) {
          callback._invoke([value]) |> ignore
        }
      }
      guard owner.context is Some(audio) else {
        report(
          @core.new(@core.global_this()._get("Error"), [
            @core.any(
              "再生ボタンを押して音声を有効にしてください。",
            ),
          ]),
        )
        return fn() { () }
      }
      if !@core.equal(audio._get("state"), @core.any("running")) {
        report(
          @core.new(@core.global_this()._get("Error"), [
            @core.any(
              "再生ボタンを押して音声を有効にしてください。",
            ),
          ]),
        )
        return fn() { () }
      }
      let mixer = owner.pending.unwrap_or_else(fn() {
        @browser_media.AudioMixer::new(tracks, @core.undefined())
      })
      owner.pending = None
      let position = latest.get_current().unwrap().0 / 1000.0
      let playback : AudioPlayback = {
        context: audio,
        mixer,
        clock: audio._get("currentTime").cast(),
        position,
        nodes: @collection.JsSet::new(),
        report,
        next: position,
        state: Idle,
        timer: None,
      }
      playback.pump()
      playback.timer = Some(
        @core.global_this()._call("setInterval", [
          @core.any(fn() { playback.pump() }),
          @core.any(80),
        ]),
      )
      fn() { playback.stop() }
    },
    [@core.any(playing), @core.any(tracks), scene_id],
  )
  let unlock = fn() {
    @core.from_async(async fn() {
      let audio_context_type = @core.global_this()._get("AudioContext")
      if tracks.is_empty() && @core.is_undefined(audio_context_type) {
        return
      }
      owner.cancel()
      let generation = owner.generation
      let audio = match owner.context {
        Some(audio) => audio
        None => {
          let audio = @core.throwable(fn() {
            @core.new(audio_context_type, [
              @core.from_entries([("sampleRate", @core.any(@audio.sample_rate))]),
            ])
          })
          owner.context = Some(audio)
          audio
        }
      }
      ui_call(audio, "resume", []) |> ignore
      if generation != owner.generation || tracks.is_empty() {
        return
      }
      let mixer = @browser_media.AudioMixer::new(tracks, @core.undefined())
      owner.pending = Some(mixer)
      errdefer {
        mixer.dispose()
        if generation == owner.generation {
          owner.pending = None
        }
      }
      mixer.prepare().wait()
      if generation != owner.generation {
        mixer.dispose()
      }
    })
    |> ui_native_errors
  }
  @core.from_entries([
    ("cancel", @core.any(fn() { owner.cancel() })),
    ("unlock", @core.any(unlock)),
  ])
}
