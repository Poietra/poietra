///|
pub fn studio(input : @core.Any) -> @react.Element {
  let store = input._get("store")
  let (state, publish) = @react.use_state_lazy(fn() { studio_initial(store) })
  let project = use_store_field(store, "project")
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
  let context = @react.use_memo(
    fn() {
      let context = ui_shallow_copy(callbacks)
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
        context._set(key, value)
      }
      for
        (key, value) in [
          ("selection", document.selection.native()),
          ("selectedIds", @core.any(host_array(document.objects))),
          ("setSelectedIds", callbacks._get("chooseObjects")),
          ("tool", @core.any(studio_tool_name(state.tool))),
          ("kernel", input._get("kernel")),
          ("renderer", input._get("renderer")),
          ("createFramePainter", input._get("createFramePainter")),
          ("positionSource", @core.any(self.position)),
          ("previewScope", @core.any(scope.name())),
          ("viewingPlayback", @core.any(state.viewing())),
          ("pathEditing", @core.any(state.path_editing)),
        ] {
        context._set(key, value)
      }
      context
    },
    [
      callbacks,
      store,
      scene,
      @core.any(document.composition),
      @core.any(state.playing()),
      @core.any(state.viewing()),
      document.transition,
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
  let controls = @react.use_memo(
    fn() {
      let value = ui_shallow_copy(context)
      value._set("setSelectedIds", callbacks._get("setSelectedIds"))
      value
    },
    [context, callbacks],
  )
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
      { "value": context },
      [
        component(studio_audio, { "controller": @core.any(self) }, []),
        studio_view(self, imports, right_panel, image_input, media_input),
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
