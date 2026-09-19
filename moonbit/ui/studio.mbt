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
) -> StudioFrames {
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
      match @boundary.playback_static_key(program, state.playhead) {
        Some(key) => @core.any("hold-\{key}")
        None => @core.any(state.playhead)
      }
    _ => @core.any(state.playhead)
  }
  let current = @react.use_memo(
    fn() {
      match program {
        Some(program) =>
          if state.viewing() {
            @boundary.playback_frame(program, state.playhead)
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
  let preview = state.cursor == TransitionPosition || doc.local_time > 0.0
  let transition = @react.use_memo(
    fn() {
      if program is Some(program) && truthy(doc.transition) && preview {
        @boundary.playback_transition(
          program,
          doc.transition._get("id").cast(),
          doc.local_time,
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
      @core.any(doc.local_time),
      @core.any(state.render_revision),
    ],
  )
  { current, from: sides.0, to: sides.1, transition, }
}

///|
pub fn studio(input : @core.Any) -> @react.Element {
  let store = input._get("store")
  let snapshot : @core.Any = @react.use_sync_external_store(
    store._get("subscribe").cast(),
    store._get("snapshot").cast(),
  )
  let chat : FixedArray[@core.Any] = @react.use_sync_external_store(
    store._get("chat")._get("subscribe").cast(),
    store._get("chat")._get("snapshot").cast(),
  )
  let (state, publish) = @react.use_state_lazy(fn() { studio_initial(store) })
  let project = snapshot._get("project")
  let scene = studio_scene(project, state.scene_id)
  let segments : FixedArray[@core.Any] = @react.use_memo(
    fn() {
      if truthy(scene) {
        @boundary.scene_segments(scene).cast()
      } else {
        []
      }
    },
    [scene],
  )
  let document = studio_document(project, scene, state, segments)
  let reference = @react.use_ref((None : StudioController?))
  let self = match reference.get_current() {
    Some(self) => self
    None => {
      let self : StudioController = {
        state,
        input,
        document,
        media: @core.undefined(),
        mounted: false,
        generation: 0,
        clock: { time: 0.0, position: 0.0, end: 0.0, },
        toast_timer: None,
        copy_timer: None,
        save: None,
        publish,
      }
      reference.set_current(Some(self))
      self
    }
  }
  self.state = state
  self.input = input
  self.document = document
  self.media = use_media_playback(
    scene,
    state.playhead,
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
  let right_panel = @react.use_ref((None : @core.Any?))
  let image_input = @react.use_ref((None : @core.Any?))
  let media_input = @react.use_ref((None : @core.Any?))
  let composing = @react.use_ref(Some(false))
  let paste_in_place = @react.use_ref(Some(false))
  use_studio_effects(self, chat, right_panel)
  let callbacks = @react.use_memo(fn() { studio_callbacks(self) }, [
    @core.any(self),
  ])
  let controls = ui_shallow_copy(callbacks)
  for
    (key, value) in [
      ("store", store),
      ("scene", scene),
      ("compositionId", @core.any(document.composition)),
      ("playing", @core.any(state.playing())),
      ("transportView", @core.any(state.viewing())),
      ("transition", document.transition),
      ("activeIds", @core.any(host_array(document.objects))),
      ("composing", composing.as_any()),
      ("pasteInPlace", paste_in_place.as_any()),
    ] {
    controls._set(key, value)
  }
  let imports = use_editor_imports(controls)
  use_editor_keyboard(controls)
  let clipboard = ui_shallow_copy(controls)
  for
    key in ["imageRequest", "mediaRequest", "setImportingImage", "importFiles"] {
    clipboard._set(key, imports._get(key))
  }
  clipboard._set(
    "rehostImageAssets",
    input._get("services")._get("rehostImageAssets"),
  )
  use_editor_clipboard(clipboard)
  let frames = use_studio_frames(document, state, input._get("kernel"))
  if !truthy(project) || !truthy(scene) {
    return h("div", { "className": @core.any("loading-screen") }, [
      h(
        "img",
        { "src": @core.any("/poietra.svg"), "alt": @core.any("Poietra") },
        [],
      ),
      h("span", Map([]), ["Opening your studio"]),
      h("div", { "className": @core.any("loading-line") }, []),
      component(
        connection_status,
        {
          "snapshot": snapshot,
          "onRetry": store._get("retryConnection"),
          "expanded": @core.any(true),
        },
        [],
      ),
    ])
  }
  let context = ui_shallow_copy(controls)
  let scope = match state.transport {
    Playing(scope) | Preparing(_, scope) => scope
    Stopped =>
      if state.cursor == TransitionPosition {
        SelectedTransition
      } else {
        WholeScene
      }
  }
  for
    (key, value) in [
      ("selection", document.selection.native()),
      ("selectedIds", @core.any(host_array(document.objects))),
      ("tool", @core.any(studio_tool_name(state.tool))),
      ("kernel", input._get("kernel")),
      ("renderer", input._get("renderer")),
      ("createFramePainter", input._get("createFramePainter")),
      ("playhead", @core.any(state.playhead)),
      ("previewScope", @core.any(scope.name())),
      ("viewingPlayback", @core.any(state.viewing())),
      ("pathEditing", @core.any(state.path_editing)),
      ("peers", snapshot._get("peers")),
      ("appendComposition", @core.any(fn() { self.append() })),
      (
        "requestTextEdit",
        @core.any(fn(object : String, composition : String) {
          self.text_edit(object, composition)
        }),
      ),
      (
        "setSelectedIds",
        @core.any(fn(ids : FixedArray[String]) {
          self.choose(Array::makei(ids.length(), fn(i) { ids[i] }))
        }),
      ),
      (
        "seek",
        @core.any(fn(time : Double, value : @core.Any) {
          let scope = if @core.is_undefined(value) {
            if truthy(self.document.transition) && !self.state.viewing() {
              SelectedTransition
            } else {
              WholeScene
            }
          } else {
            studio_scope(value)
          }
          self.seek(time, scope)
        }),
      ),
    ] {
    context._set(key, value)
  }
  ui("Tooltip", "Provider", { "delay": @core.any(450) }, [
    keyed_element(
      editor_context_runtime()._get("Provider"),
      { "value": context },
      [
        studio_view(
          self, snapshot, chat, imports, frames, right_panel, image_input, media_input,
        ),
      ],
    ),
  ])
}
