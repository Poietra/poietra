///|
priv enum SoundTarget {
  MotionStart
  MotionMiddle
  MotionEnd
  CurrentPosition
}

///|
priv struct SoundSettings {
  preset : Int
  duration : Double
  pitch : Double
  volume : Double
  seed : UInt
  target : SoundTarget
  sync : @sound_effects.SyncPoint
  channel : @scene.PropertyChannel?
}

///|
priv enum SoundStatus {
  Quiet
  Listening
  Storing(Double)
}

///|
priv struct SoundPaletteView {
  editor : EditorView
  close : () -> Unit
  added : (String) -> Unit
}

///|
priv struct SoundSession {
  mut editor : EditorView
  mut mounted : Bool
  mut generation : Int
  mut request : @core.Any?
  mut context : @core.Any?
  mut source : (@core.Any, @core.Any)?
  mut cached : ((Int, Double, Double, UInt), @sound_effects.Sound)?
  status : (SoundStatus) -> Unit
  error : (String) -> Unit
  added : (String) -> Unit
}

///|
fn sound_range(
  editor : EditorView,
  channel : @scene.PropertyChannel?,
) -> @editor.TimingRange {
  let segment = @boundary.read_scene_segments(editor.scene)
    .iter()
    .find_first(fn(segment) { segment.id == editor.selection.id() })
  guard segment is Some(segment) else { return { start: 0.0, duration: 0.0, } }
  let timings : Array[@scene.Timing] = []
  if editor.selection is TransitionSelection(id) {
    let transition = editor.scene._get("transitions")._get(id)
    for object_id in editor.selected_ids {
      let animation = @boundary.visible_animation(
        editor.scene,
        transition,
        object_id,
      )
      if truthy(animation) {
        let track = animation._get("track")
        match channel {
          Some(channel) =>
            timings.push(
              @boundary.read_timing(
                @boundary.get_property_timing(
                  track,
                  @editor.property_channel_name(channel),
                ),
              ),
            )
          None => {
            timings.push(@boundary.read_timing(track))
            for channel in @scene.property_channels() {
              let name = @editor.property_channel_name(channel)
              if @boundary.has_property_timing(track, name) {
                timings.push(
                  @boundary.read_timing(
                    @boundary.get_property_timing(track, name),
                  ),
                )
              }
            }
          }
        }
      }
    }
  }
  @editor.sound_cue_range(segment, timings)
}

///|
fn sound_target_time(
  settings : SoundSettings,
  range : @editor.TimingRange,
  time : Double,
) -> Double {
  match settings.target {
    MotionStart => range.start
    MotionMiddle => range.start + range.duration / 2.0
    MotionEnd => range.start + range.duration
    CurrentPosition => time
  }
}

///|
fn sound_failure(message : String) -> Unit raise {
  @core.throwable(fn() { @core.throw_error(message) })
}

///|
fn[T] sound_result(value : Result[T, String]) -> T raise {
  match value {
    Ok(value) => value
    Err(message) => {
      sound_failure(message)
      abort("unreachable")
    }
  }
}

///|
fn SoundSession::render(
  self : SoundSession,
  settings : SoundSettings,
) -> @sound_effects.Sound raise {
  let key = (settings.preset, settings.duration, settings.pitch, settings.seed)
  if self.cached is Some((previous, sound)) && previous == key {
    return sound
  }
  let sound = sound_result(
    @sound_effects.synthesize(
      @sound_effects.presets()[settings.preset].voice,
      settings.duration,
      settings.pitch,
      settings.seed,
    ),
  )
  self.cached = Some((key, sound))
  sound
}

///|
fn SoundSession::stop_preview(self : SoundSession) -> Unit {
  self.generation += 1
  if self.source is Some((source, gain)) {
    self.source = None
    source._set("onended", @core.null())
    @core.throwable(fn() { source._call("stop", []) |> ignore }) catch {
      _ => ()
    }
    source._call("disconnect", []) |> ignore
    gain._call("disconnect", []) |> ignore
  }
}

///|
fn SoundSession::cancel(self : SoundSession) -> Unit {
  self.stop_preview()
  if self.request is Some(request) {
    self.request = None
    request._call("abort", []) |> ignore
  }
  if self.mounted {
    (self.status)(Quiet)
  }
}

///|
fn SoundSession::dispose(self : SoundSession) -> Unit {
  self.mounted = false
  self.cancel()
  self.cached = None
  if self.context is Some(context) {
    self.context = None
    let closing : @core.Promise[@core.Any] = context._call("close", []).cast()
    closing.catch_(fn(_) { @core.Promise::resolve(@core.undefined()) })
    |> ignore
  }
}

///|
fn SoundSession::preview(
  self : SoundSession,
  settings : SoundSettings,
  time : Double,
) -> @core.Promise[Unit] {
  self.stop_preview()
  let generation = self.generation
  @core.from_async(async fn() {
    try {
      (self.error)("")
      let sound = self.render(settings)
      let playback = sound_result(
        @editor.sound_placement(
          sound.duration,
          sound.cue(settings.sync),
          sound_target_time(
            settings,
            sound_range(self.editor, settings.channel),
            time,
          ),
        ),
      )
      let context = match self.context {
        Some(context) => context
        None => {
          let context_type = @core.global_this()._get("AudioContext")
          if @core.is_undefined(context_type) {
            sound_failure(
              "このブラウザでは効果音を試聴できません。",
            )
          }
          let context = @core.throwable(fn() {
            @core.new(context_type, [
              host_record({
                "sampleRate": @core.any(@sound_effects.sample_rate),
              }),
            ])
          })
          self.context = Some(context)
          context
        }
      }
      let resumed : @core.Promise[@core.Any] = @core.throwable(fn() {
        context._call("resume", [])
      }).cast()
      resumed.wait() |> ignore
      if !self.mounted || self.generation != generation {
        return
      }
      let buffer = @core.throwable(fn() {
        context._call("createBuffer", [
          @core.any(1),
          @core.any(sound.samples.length()),
          @core.any(@sound_effects.sample_rate),
        ])
      })
      @core.throwable(fn() {
        buffer
        ._call("getChannelData", [@core.any(0)])
        ._call("set", [@core.any(sound.samples)])
      })
      |> ignore
      let source = context._call("createBufferSource", [])
      let gain = context._call("createGain", [])
      self.source = Some((source, gain))
      source._set("buffer", buffer)
      gain._get("gain")._set("value", @core.any(settings.volume / 100.0))
      source._call("connect", [gain]) |> ignore
      gain._call("connect", [context._get("destination")]) |> ignore
      source._set(
        "onended",
        @core.any(fn() {
          if self.mounted && self.generation == generation {
            self.stop_preview()
            (self.status)(Quiet)
          }
        }),
      )
      @core.throwable(fn() {
        source._call("start", [
          @core.any(0),
          @core.any(playback.offset / 1000.0),
          @core.any(playback.duration / 1000.0),
        ])
      })
      |> ignore
      (self.status)(Listening)
    } catch {
      error =>
        if self.mounted && self.generation == generation {
          self.stop_preview()
          (self.status)(Quiet)
          (self.error)(
            error_message(
              ui_native_error(error),
              "効果音を試聴できませんでした。",
            ),
          )
        }
    }
  })
}

///|
fn SoundSession::current_scene(self : SoundSession) -> @core.Any raise {
  let id : String = self.editor.scene._get("id").cast()
  let scene = @core.throwable(fn() { self.editor.store._call("project", []) })
    ._get("scenes")
    ._get(id)
  if !truthy(scene) ||
    !truthy(scene._get("compositions")._get(self.editor.composition_id)) ||
    !@boundary.read_scene_segments(scene).any(fn(segment) {
      segment.id == self.editor.selection.id()
    }) {
    sound_failure(
      "追加先が削除されました。場面を選び直してください。",
    )
  }
  if !truthy(scene._get("audioTracks")) {
    sound_failure(
      "音声トラックを準備しています。同期完了後に追加してください。",
    )
  }
  if @core.object_keys(scene._get("audioTracks")).length() >= 100 {
    sound_failure("音声トラックは 100 件まで追加できます。")
  }
  scene
}

///|
fn SoundSession::insert(
  self : SoundSession,
  settings : SoundSettings,
  time : Double,
) -> @core.Promise[Unit] {
  if self.request is Some(_) ||
    !self.mounted ||
    self.editor.playing ||
    self.editor.viewing_playback {
    return @core.Promise::resolve(())
  }
  self.stop_preview()
  let generation = self.generation
  let controller = new_controller()
  self.request = Some(controller)
  let signal = controller._get("signal")
  let active = fn() {
    self.mounted && self.generation == generation && !ui_aborted(signal)
  }
  @core.from_async(async fn() {
    defer (if active() {
      self.request = None
      (self.status)(Quiet)
    })
    try {
      (self.error)("")
      self.current_scene() |> ignore
      let sound = self.render(settings)
      let current = self.current_scene()
      sound_result(
        @editor.sound_placement(
          sound.duration,
          sound.cue(settings.sync),
          sound_target_time(
            settings,
            sound_range({ ..self.editor, scene: current, }, settings.channel),
            time,
          ),
        ),
      )
      |> ignore
      let bytes = sound.wave()
      let blob = @core.throwable(fn() {
        @core.new(@core.global_this()._get("Blob"), [
          @core.any(([@core.any(bytes)] : FixedArray[@core.Any])),
          host_record({ "type": @core.any("audio/wav") }),
        ])
      })
      (self.status)(Storing(0.0))
      let progress = fn(value : @core.Any) {
        if active() {
          (self.status)(Storing(value._get("progress").cast()))
        }
      }
      let room : String = self.editor.store._get("roomId").cast()
      let source = @browser_media.upload_media(
        room,
        blob,
        signal,
        @core.any(progress),
      ).wait()
      if !active() || self.editor.playing || self.editor.viewing_playback {
        return
      }
      // Re-read peer timing and capacity after upload, then encode one insertion
      // before publishing. No half-created track or extra gain/trim Undo item.
      let scene = self.current_scene()
      let editor = { ..self.editor, scene, }
      let playback = sound_result(
        @editor.sound_placement(
          sound.duration,
          sound.cue(settings.sync),
          sound_target_time(
            settings,
            sound_range(editor, settings.channel),
            time,
          ),
        ),
      )
      let asset : @scene.MediaAsset = {
        src: source,
        mime: "audio/wav",
        duration: sound.duration,
        width: None,
        height: None,
        hasAudio: true,
        waveform: Some(sound.waveform),
      }
      let preset = @sound_effects.presets()[settings.preset]
      let insertion = @boundary.asset_import_changes(
        scene,
        editor.composition_id,
        [@editor.ImportedAudio(preset.name, asset)],
        None,
        audio_options={ playback, volume: settings.volume / 100.0, },
      )
      @core.throwable(fn() {
        editor.store._call("edit", [insertion._get("changes")])
      })
      |> ignore
      let ids : FixedArray[String] = insertion._get("audioIds").cast()
      (self.added)(ids[0])
      (editor.actions.notify)(
        preset.name +
        " を追加しました。波形をドラッグして調整できます",
      )
    } catch {
      error =>
        if active() {
          (self.error)(
            error_message(
              ui_native_error(error),
              "効果音を追加できませんでした。",
            ),
          )
        }
    }
  })
}
