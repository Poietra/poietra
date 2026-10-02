///|
/// UI-to-UI commands are a checked contract. Native callbacks are adapted only
/// at the public JS entry points; internal callers never dispatch by name.
priv struct EditorActions {
  notify : (String) -> Unit
  select : (StudioSelection) -> Unit
  select_objects : (FixedArray[String]) -> Unit
  set_selected_ids : (FixedArray[String]) -> Unit
  append_composition : () -> Unit
  request_text_edit : (String, String) -> Unit
  set_tool : (@editor.StageTool) -> Unit
  activate_tool : (@editor.StageTool) -> Unit
  seek : (Double, StudioScope?) -> Unit
  play : (StudioScope) -> Unit
  set_playing : (Bool) -> Unit
  set_transport_view : (Bool) -> Unit
  set_path_editing : (Bool) -> Unit
  set_panel : (StudioPanel) -> Unit
  edit_moment : (Bool) -> Unit
  undo : () -> Unit
  redo : () -> Unit
}

///|
/// Native document snapshots and host resources retain their existing identity.
/// Selection, UI state and commands have an internal contract independent of the
/// public EditorContextValue object. Decode document values through boundary.
priv struct EditorView {
  store : @core.Any
  scene : @core.Any
  selection : StudioSelection
  composition_id : String
  selected_ids : FixedArray[String]
  tool : @editor.StageTool
  kernel : @core.Any
  renderer : @core.Any
  create_frame_painter : @core.Any
  position_source : StudioPosition?
  playhead : Double
  peers : FixedArray[@core.Any]
  playing : Bool
  viewing_playback : Bool
  preview_scope : StudioScope
  path_editing : Bool
  actions : EditorActions
}

///|
priv struct EditorControls {
  store : @core.Any
  scene : @core.Any
  composition_id : String
  active_ids : FixedArray[String]
  playing : Bool
  viewing_playback : Bool
  has_transition : Bool
  composing : @react.ReactRef[Bool]
  paste_in_place : @react.ReactRef[Bool]
  actions : EditorActions
}

///|
priv struct ImportView {
  image_request : @react.ReactRef[@core.Any]
  media_request : @react.ReactRef[@core.Any]
  importing_image : Bool
  media_import : ImportProgress?
  error : String
  set_importing_image : (Bool) -> Unit
  set_error : (String) -> Unit
  import_images : (FixedArray[@core.Any], @scene.Point?) -> @core.Promise[Unit]
  import_files : (FixedArray[@core.Any], @scene.Point?) -> @core.Promise[Unit]
  cancel : () -> Unit
}

///|
priv struct ClipboardInput {
  controls : EditorControls
  image_request : @react.ReactRef[@core.Any]
  media_request : @react.ReactRef[@core.Any]
  set_importing_image : (Bool) -> Unit
  import_files : (FixedArray[@core.Any], @scene.Point?) -> Unit
  rehost_images : async (FixedArray[@core.Any], String, @core.Any) -> Unit
}

///|
fn StudioSelection::chat(self : StudioSelection) -> @editor.ChatSelection {
  match self {
    CompositionSelection(id) => @editor.Composition(id)
    TransitionSelection(id) => @editor.Transition(id)
  }
}

///|
fn studio_chat_selection(selection : @editor.ChatSelection) -> StudioSelection {
  match selection {
    @editor.Composition(id) => CompositionSelection(id)
    @editor.Transition(id) => TransitionSelection(id)
  }
}
