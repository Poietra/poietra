///|
pub fn studio(input : @core.Any) -> @react.Element {
  let store = input._get("store")
  let (state, publish) = @react.use_state_lazy(fn() { studio_initial(store) })
  let project = use_store_field(store, "project")
  let scene = studio_scene(project, state.scene_id)
  let segments : Array[@scene.Segment] = @react.use_memo(
    fn() {
      if truthy(scene) {
        @boundary.read_scene_segments(scene)
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
        position: { time: 0.0, listeners: @collection.JsSet::new(), },
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
  let right_panel = @react.use_ref((None : @core.Any?))
  let image_input = @react.use_ref((None : @core.Any?))
  let media_input = @react.use_ref((None : @core.Any?))
  let composing = @react.use_ref(Some(false))
  let paste_in_place = @react.use_ref(Some(false))
  use_studio_effects(self, right_panel)
  let callbacks = @react.use_memo(fn() { studio_callbacks(self) }, [
    @core.any(self),
  ])
  let scope = match state.transport {
    Playing(scope) | Preparing(_, scope) => scope
    Stopped =>
      if state.cursor == TransitionPosition {
        SelectedTransition
      } else {
        WholeScene
      }
  }
  let context : EditorView = @react.use_memo(
    fn() {
      {
        store,
        scene,
        selection: document.selection,
        composition_id: document.composition,
        selected_ids: host_array(document.objects),
        tool: state.tool,
        kernel: input._get("kernel"),
        renderer: input._get("renderer"),
        create_frame_painter: input._get("createFramePainter"),
        position_source: Some(self.position),
        playhead: 0.0,
        peers: [],
        playing: state.playing(),
        viewing_playback: state.viewing(),
        preview_scope: scope,
        path_editing: state.path_editing,
        actions: callbacks,
      }
    },
    [
      @core.any(callbacks),
      store,
      scene,
      @core.any(document.composition),
      @core.any(state.playing()),
      @core.any(state.viewing()),
      @core.any(state.objects),
      @core.any(document.selection.id()),
      @core.any(document.selection is TransitionSelection(_)),
      @core.any(studio_tool_name(state.tool)),
      @core.any(state.path_editing),
      @core.any(scope.name()),
      input._get("kernel"),
      input._get("renderer"),
      input._get("createFramePainter"),
    ],
  )
  let native_callbacks = @react.use_memo(
    fn() { native_editor_actions(callbacks) },
    [@core.any(callbacks)],
  )
  let public_context = @react.use_memo(
    fn() { native_editor_view(context, native_callbacks) },
    [@core.any(context), native_callbacks],
  )
  let controls : EditorControls = @react.use_memo(
    fn() {
      {
        store,
        scene,
        composition_id: document.composition,
        active_ids: context.selected_ids,
        playing: context.playing,
        viewing_playback: context.viewing_playback,
        has_transition: truthy(document.transition),
        composing,
        paste_in_place,
        actions: callbacks,
      }
    },
    [@core.any(context), @core.any(callbacks), document.transition],
  )
  let imports = use_import_controls(controls)
  use_keyboard_controls(controls)
  let rehost_images = @react.use_memo(
    fn() { native_image_rehost(input._get("services")) },
    [input._get("services")],
  )
  use_clipboard_controls({
    controls,
    image_request: imports.image_request,
    media_request: imports.media_request,
    set_importing_image: imports.set_importing_image,
    import_files: fn(files, point) {
      (imports.import_files)(files, point) |> ignore
    },
    rehost_images,
  })
  if !truthy(project) || !truthy(scene) {
    return h("div", { "className": @core.any("loading-screen") }, [
      h(
        "img",
        { "src": @core.any("/poietra.svg"), "alt": @core.any("Poietra") },
        [],
      ),
      h("span", Map([]), ["Opening your studio"]),
      h("div", { "className": @core.any("loading-line") }, []),
      component(studio_loading_connection, { "store": store }, []),
    ])
  }
  ui("Tooltip", "Provider", { "delay": @core.any(450) }, [
    keyed_element(
      editor_context_runtime()._get("Provider"),
      { "value": public_context },
      [
        component(
          studio_position_provider,
          { "position": @core.any(self.position) },
          [
            component(studio_audio, { "controller": @core.any(self) }, []),
            @react.provider(
              typed_editor_context,
              [
                studio_view(
                  self, imports, right_panel, image_input, media_input,
                ),
              ],
              value=Some(context),
            ),
          ],
        ),
      ],
    ),
  ])
}

///|
fn studio_loading_connection(input : @core.Any) -> @react.Element {
  let store = input._get("store")
  let snapshot : @core.Any = @react.use_sync_external_store(
    store._get("subscribe").cast(),
    store._get("snapshot").cast(),
  )
  component(
    connection_status,
    {
      "snapshot": snapshot,
      "onRetry": store._get("retryConnection"),
      "expanded": @core.any(true),
    },
    [],
  )
}
