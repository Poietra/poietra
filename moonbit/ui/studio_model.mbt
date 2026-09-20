///|
priv enum StudioSelection {
  CompositionSelection(String)
  TransitionSelection(String)
}

///|
fn StudioSelection::id(self : StudioSelection) -> String {
  match self {
    CompositionSelection(id) | TransitionSelection(id) => id
  }
}

///|
fn StudioSelection::native(self : StudioSelection) -> @core.Any {
  host_record({
    "id": @core.any(self.id()),
    "kind": @core.any(
      match self {
        CompositionSelection(_) => "composition"
        TransitionSelection(_) => "transition"
      },
    ),
  })
}

///|
fn studio_selection(value : @core.Any) -> StudioSelection {
  let id : String = value._get("id").cast()
  if @core.equal(value._get("kind"), @core.any("transition")) {
    TransitionSelection(id)
  } else {
    CompositionSelection(id)
  }
}

///|
priv enum StudioScope {
  WholeScene
  SelectedTransition
} derive(Eq)

///|
priv enum StudioTransport {
  Stopped
  Preparing(Int, StudioScope)
  Playing(StudioScope)
}

///|
priv enum StudioCursor {
  SelectedState
  ScenePosition
  TransitionPosition
} derive(Eq)

///|
priv enum StudioPanel {
  DesignPanel
  ChatPanel
} derive(Eq)

///|
priv struct TextEditTarget {
  scene : String
  composition : String
  object : String
}

///|
priv struct StudioState {
  scene_id : String
  selection : StudioSelection
  objects : Array[String]
  tool : @editor.StageTool
  transport : StudioTransport
  cursor : StudioCursor
  path_editing : Bool
  zoom : Double
  panel : StudioPanel
  project_open : Bool
  preview_open : Bool
  export_open : Bool
  share_open : Bool
  shortcuts_open : Bool
  image_drag : Bool
  text_edit : TextEditTarget?
  user_name : String
  copied : Bool
  saving : Bool
  toast : String
  audio_error : String
  render_error : String
  render_revision : Int
  render_attempt : Int
}

///|
fn StudioState::playing(self : StudioState) -> Bool {
  self.transport is Playing(_)
}

///|
fn StudioState::viewing(self : StudioState) -> Bool {
  self.cursor == ScenePosition
}

///|
fn studio_initial(store : @core.Any) -> StudioState {
  let url = @core.new(@core.global_this()._get("URL"), [
    @core.global_this()._get("location")._get("href"),
  ])
  let params = url._get("searchParams")
  {
    scene_id: "scene-1",
    selection: CompositionSelection("comp-1"),
    objects: [],
    tool: @editor.SelectTool,
    transport: Stopped,
    cursor: SelectedState,
    path_editing: false,
    zoom: 1.0,
    panel: DesignPanel,
    project_open: truthy(params._call("has", [@core.any("projects")])) ||
    truthy(params._call("has", [@core.any("auth_error")])),
    preview_open: false,
    export_open: false,
    share_open: false,
    shortcuts_open: false,
    image_drag: false,
    text_edit: None,
    user_name: store._get("userName").cast(),
    copied: false,
    saving: false,
    toast: "",
    audio_error: "",
    render_error: "",
    render_revision: 0,
    render_attempt: 0,
  }
}

///|
priv struct StudioDocument {
  project : @core.Any
  scene : @core.Any
  scene_id : String
  selection : StudioSelection
  composition : String
  transition : @core.Any
  objects : Array[String]
  total : Double
  selected : @core.Any
  segments : FixedArray[@core.Any]
}

///|
fn studio_scene(project : @core.Any, id : String) -> @core.Any {
  if @core.is_nullish(project) {
    return @core.undefined()
  }
  let scenes = project._get("scenes")
  let scene = scenes._get(id)
  if !@core.is_nullish(scene) {
    scene
  } else {
    let order : FixedArray[String] = project._get("sceneOrder").cast()
    if order.is_empty() {
      @core.undefined()
    } else {
      scenes._get(order[0])
    }
  }
}

///|
fn studio_document(
  project : @core.Any,
  scene : @core.Any,
  state : StudioState,
  segments : FixedArray[@core.Any],
) -> StudioDocument {
  let has_scene = !@core.is_nullish(scene)
  let valid = has_scene &&
    !@core.is_nullish(
      scene
      ._get(
        match state.selection {
          CompositionSelection(_) => "compositions"
          TransitionSelection(_) => "transitions"
        },
      )
      ._get(state.selection.id()),
    )
  let selection = if valid {
    state.selection
  } else {
    let order : FixedArray[String] = if has_scene {
      scene._get("compositionOrder").cast()
    } else {
      []
    }
    CompositionSelection(if order.is_empty() { "" } else { order[0] })
  }
  let transition = match selection {
    TransitionSelection(id) if has_scene => scene._get("transitions")._get(id)
    _ => @core.undefined()
  }
  let composition = if truthy(transition) {
    transition._get("toId").cast()
  } else {
    selection.id()
  }
  let selected = segments
    .iter()
    .find_first(fn(segment) {
      @core.equal(segment._get("id"), @core.any(selection.id()))
    })
    .unwrap_or(@core.undefined())
  let total = if segments.is_empty() {
    0.0
  } else {
    let last = segments[segments.length() - 1]
    let start : Double = last._get("start").cast()
    start + (last._get("duration").cast() : Double)
  }
  {
    project,
    scene,
    scene_id: if has_scene {
      scene._get("id").cast()
    } else {
      ""
    },
    selection,
    composition,
    transition,
    total,
    selected,
    segments,
    objects: state.objects.filter(fn(id) {
      has_scene && truthy(scene._get("objects")._get(id))
    }),
  }
}

///|
fn studio_tool(value : String) -> @editor.StageTool {
  if value == "select" {
    @editor.SelectTool
  } else {
    @editor.DrawTool(@scene.object_kind(value).unwrap())
  }
}

///|
fn studio_tool_name(value : @editor.StageTool) -> String {
  match value {
    SelectTool => "select"
    DrawTool(kind) => @scene.object_kind_name(kind)
  }
}

///|
fn studio_scope(value : @core.Any) -> StudioScope {
  if @core.equal(value, @core.any("transition")) {
    SelectedTransition
  } else {
    WholeScene
  }
}

///|
fn StudioScope::name(self : StudioScope) -> String {
  match self {
    WholeScene => "scene"
    SelectedTransition => "transition"
  }
}

///|
priv struct StudioClock {
  time : Double
  position : Double
  end : Double
}

///|
priv struct StudioController {
  mut state : StudioState
  mut input : @core.Any
  mut document : StudioDocument
  mut media : @core.Any
  mut mounted : Bool
  mut generation : Int
  mut clock : StudioClock
  position : StudioPosition
  mut toast_timer : @core.Any?
  mut copy_timer : @core.Any?
  mut save : @core.Any?
  publish : (StudioState) -> Unit
}

///|
fn StudioController::update(
  self : StudioController,
  state : StudioState,
) -> Unit {
  self.state = state
  if self.mounted {
    (self.publish)(state)
  }
}

///|
fn StudioController::notify(self : StudioController, message : String) -> Unit {
  if self.toast_timer is Some(timer) {
    cancel_timer(timer)
  }
  self.update({ ..self.state, toast: message, })
  self.toast_timer = Some(
    schedule_timer(
      fn() {
        self.toast_timer = None
        self.update({ ..self.state, toast: "", })
      },
      4000,
    ),
  )
}

///|
fn StudioController::stop(self : StudioController) -> Unit {
  self.generation += 1
  if truthy(self.media) {
    self.media._call("cancel", []) |> ignore
  }
  self.update({ ..self.state, transport: Stopped, })
}

///|
fn studio_segment_start(scene : @core.Any, id : String) -> Double {
  let segments : FixedArray[@core.Any] = @boundary.scene_segments(scene).cast()
  segments
  .iter()
  .find_first(fn(segment) { @core.equal(segment._get("id"), @core.any(id)) })
  .map(fn(segment) { segment._get("start").cast() })
  .unwrap_or(0.0)
}
