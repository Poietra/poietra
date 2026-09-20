///|
priv struct StudioFrames {
  current : @core.Any
  from : @core.Any
  to : @core.Any
  transition : @core.Any
}

///|
fn use_studio_frames(
  doc : StudioDocument,
  state : StudioState,
  kernel : @core.Any,
  time : Double,
) -> StudioFrames {
  let local_time = doc.local_time(time)
  let needs_program = state.viewing() || truthy(doc.transition)
  let program = @react.use_memo(
    fn() {
      if truthy(doc.scene) && needs_program {
        Some(@boundary.prepare_playback(doc.scene, kernel))
      } else {
        None
      }
    },
    [doc.scene, kernel, @core.any(needs_program)],
  )
  let clock_key = match program {
    Some(program) if state.viewing() =>
      match @boundary.playback_static_key(program, time) {
        Some(key) => @core.any("hold-\{key}")
        None => @core.any(time)
      }
    _ => @core.any(time)
  }
  let current = @react.use_memo(
    fn() {
      match program {
        Some(program) =>
          if state.viewing() {
            @boundary.playback_frame(program, time)
          } else {
            @boundary.playback_composition(
              program,
              doc.composition,
              @core.undefined(),
            )
          }
        None =>
          if truthy(doc.scene) {
            @boundary.composition_frame(
              doc.scene,
              doc.scene._get("compositions")._get(doc.composition),
              @core.undefined(),
            )
          } else {
            @core.undefined()
          }
      }
    },
    [
      @core.any(program),
      doc.scene,
      @core.any(state.viewing()),
      clock_key,
      @core.any(doc.composition),
      @core.any(state.render_revision),
    ],
  )
  let sides = @react.use_memo(
    fn() {
      if program is Some(program) && truthy(doc.transition) {
        (
          @boundary.playback_composition(
            program,
            doc.transition._get("fromId").cast(),
            @core.undefined(),
          ),
          @boundary.playback_composition(
            program,
            doc.transition._get("toId").cast(),
            @core.undefined(),
          ),
        )
      } else {
        (@core.undefined(), @core.undefined())
      }
    },
    [@core.any(program), doc.transition, @core.any(state.render_revision)],
  )
  let preview = state.cursor == TransitionPosition || local_time > 0.0
  let transition = @react.use_memo(
    fn() {
      if program is Some(program) && truthy(doc.transition) && preview {
        @boundary.playback_transition(
          program,
          doc.transition._get("id").cast(),
          local_time,
          @core.undefined(),
        )
      } else {
        @core.undefined()
      }
    },
    [
      @core.any(program),
      doc.transition,
      @core.any(preview),
      @core.any(local_time),
      @core.any(state.render_revision),
    ],
  )
  { current, from: sides.0, to: sides.1, transition, }
}

///|
fn studio_audio(input : @core.Any) -> @react.Element {
  let self : StudioController = input._get("controller").cast()
  let state = self.state
  let time = use_studio_position(self.position)
  self.media = use_media_playback(
    self.document.scene,
    time,
    state.playing() && !state.preview_open,
    @core.any(fn(error : @core.Any) {
      self.stop()
      self.update({
        ..self.state,
        audio_error: error_message(
          error, "音声を再生できませんでした。",
        ),
      })
    }),
  )
  @core.null().cast()
}

///|
fn studio_stage_view(input : @core.Any) -> @react.Element {
  let self : StudioController = input._get("controller").cast()
  let time = use_studio_position(self.position)
  let frames = use_studio_frames(
    self.document,
    self.state,
    self.input._get("kernel"),
    time,
  )
  if truthy(self.document.transition) && !self.state.viewing() {
    @react.fragment(studio_transition_stages(self, frames, time))
  } else {
    studio_composition_stage(self, frames)
  }
}

///|
fn studio_playback_panel(input : @core.Any) -> @react.Element {
  let self : StudioController = input._get("controller").cast()
  let time = use_studio_position(self.position)
  component(
    playback_panel,
    {
      "scene": self.document.scene,
      "segment": self.document.segment_at(time),
      "playhead": @core.any(time),
      "onEdit": @core.any(fn() { self.edit_moment(false) }),
    },
    [],
  )
}
