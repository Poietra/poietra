///|
pub fn stage(input : @core.Any) -> @react.Element {
  let state = use_editor_state()
  let peers = use_editor_peers(state)
  let editor = { ..state, peers, }
  let scene = editor.scene
  let store = editor.store
  let scene_id : String = scene._get("id").cast()
  let composition_id : String = input._get("compositionId").cast()
  let frame = input._get("frame")
  let width : Double = frame._get("width").cast()
  let height : Double = frame._get("height").cast()
  let zoom = optional_number(input, "zoom", 1.0)
  let interactive = @core.is_undefined(input._get("interactive")) ||
    truthy(input._get("interactive"))
  let state_editing = @core.is_undefined(input._get("stateEditing")) ||
    truthy(input._get("stateEditing"))
  let prefix = optional_string(input._get("prefix")).unwrap_or("main")
  let tool = editor.tool
  let tool_name = studio_tool_name(tool)
  let playing = editor.playing
  let can_edit = interactive && !playing
  let renderer = editor.renderer
  let container = @react.use_ref((None : @core.Any?))
  let surface = @react.use_ref((None : @core.Any?))
  let gesture = @react.use_ref((None : StageGesture?))
  let cursor_time = @react.use_ref(Some(0.0))
  let (size, set_size) = @react.use_state(@exporting.Size::{
    width: 800.0,
    height: 450.0,
  })
  let (marquee, set_marquee) = @react.use_state((None : @geometry.Rectangle?))
  let (draw_preview, set_draw_preview) = @react.use_state(
    (None : @scene.ObjectState?),
  )
  let (painted, set_painted) = @react.use_state((None : StagePresentation?))
  let (failed_canvas, set_failed_canvas) = @react.use_state((None : String?))
  let (hover_id, set_hover_id) = @react.use_state("")
  let feedback = use_operation_feedback_state(
    "\{scene_id}:\{composition_id}:\{prefix}",
  )
  @react.use_effect(
    fn() {
      guard container.get_current() is Some(element) else { return fn() { () } }
      let observer = @core.new(@core.global_this()._get("ResizeObserver"), [
        @core.any(fn(entries : FixedArray[@core.Any]) {
          let rect = stage_bounds(entries[0]._get("contentRect"))
          let scale = (rect.width / width).min(rect.height / height) * zoom
          set_size({ width: width * scale, height: height * scale, })
        }),
      ])
      observer._call("observe", [element]) |> ignore
      fn() { observer._call("disconnect", []) |> ignore }
    },
    [@core.any(width), @core.any(height), @core.any(zoom)],
  )
  let drawing_kind = match gesture.get_current() {
    Some({ mode: DrawObject(kind), .. }) => Some(kind)
    _ => None
  }
  let drawn_frame = @react.use_memo(
    fn() {
      if draw_preview is Some(state) && drawing_kind is Some(kind) {
        let next = ui_shallow_copy(frame)
        let objects : FixedArray[@core.Any] = frame._get("objects").cast()
        let drawing = host_record({
          "object": host_record({
            "id": @core.any("drawing-preview"),
            "kind": @core.any(@scene.object_kind_name(kind)),
            "name": @core.any(""),
            "groupId": @core.null(),
            "locked": @core.any(false),
            "order": @core.any(999),
          }),
          "state": @boundary.write_object_state(state),
          "writeProgress": @core.any(1),
          "order": @core.any("together"),
        })
        next._set(
          "objects",
          @core.any(
            FixedArray::makei(objects.length() + 1, fn(i) {
              if i < objects.length() {
                objects[i]
              } else {
                drawing
              }
            }),
          ),
        )
        next
      } else {
        frame
      }
    },
    [frame, @core.any(draw_preview), @core.any(drawing_kind)],
  )
  let key = "\{scene_id}:\{composition_id}:\{prefix}:" +
    string_value(@core.any(width)) +
    ":" +
    string_value(@core.any(height)) +
    ":" +
    string_value(@core.any(interactive)) +
    ":" +
    string_value(@core.any(state_editing)) +
    ":" +
    drawing_kind.map(@scene.object_kind_name).unwrap_or("idle")
  let factory = editor.create_frame_painter
  let prepared = use_frame_preparation(
    drawn_frame,
    renderer,
    key,
    enabled=!truthy(factory) || failed_canvas == Some(key),
  )
  let canvas_visible = truthy(factory) &&
    painted
    .map(fn(value) {
      value.key == key &&
      value.width == size.width &&
      value.height == size.height
    })
    .unwrap_or(false)
  let displayed = if canvas_visible {
    painted.unwrap().frame
  } else {
    prepared.frame
  }
  // A hidden hit surface has no consumers during active playback.
  // Retain its nodes until pause or fallback makes the current geometry useful.
  let svg_frame = if canvas_visible && playing {
    @core.undefined()
  } else {
    displayed
  }
  let svg = @react.use_memo(
    fn() {
      let options = host_record({
        "idPrefix": @core.any(prefix),
        "hitVideo": @core.any(canvas_visible),
      })
      let view = if truthy(renderer._get("frameToSvgView")) {
        SvgView(renderer._call("frameToSvgView", [displayed, options]))
      } else {
        SvgMarkup(renderer._call("frameToSvg", [displayed, options]).cast())
      }
      stage_svg(view, canvas_visible, "scene-svg")
    },
    [svg_frame, renderer, @core.any(prefix), @core.any(canvas_visible)],
  )
  let selected : FixedArray[String] = editor.selected_ids
  let controller : StageController = {
    editor,
    binding: native_stage_binding(store, renderer, scene_id, composition_id),
    scene,
    store,
    renderer,
    frame: displayed,
    surface,
    gesture,
    cursor_time,
    scene_id,
    composition_id,
    tool,
    can_edit,
    state_editing,
    selected,
    width,
    height,
    scale: width / size.width.max(1.0),
    draw: set_draw_preview,
    marquee: set_marquee,
    hover: fn(id) { set_hover_id(id.unwrap_or("")) },
    report: feedback.report,
  }
  @react.use_effect(
    fn() {
      let window = @core.global_this()._get("window")
      let cancel = fn() { controller.finish(true) }
      let key = fn(event : @core.Any) {
        if event._get("key").cast() == "Escape" &&
          gesture.get_current() is Some(_) {
          prevent_default(event)
          event._call("stopImmediatePropagation", []) |> ignore
          cancel()
        }
      }
      window._call("addEventListener", [
        @core.any("keydown"),
        @core.any(key),
        @core.any(true),
      ])
      |> ignore
      window._call("addEventListener", [@core.any("blur"), @core.any(cancel)])
      |> ignore
      fn() {
        window._call("removeEventListener", [
          @core.any("keydown"),
          @core.any(key),
          @core.any(true),
        ])
        |> ignore
        window._call("removeEventListener", [
          @core.any("blur"),
          @core.any(cancel),
        ])
        |> ignore
        cancel()
      }
    },
    [
      @core.any(scene_id),
      @core.any(composition_id),
      @core.any(tool_name),
      @core.any(interactive),
      @core.any(state_editing),
      @core.any(playing),
      @core.any(width),
      @core.any(height),
      store,
    ],
  )
  stage_view(
    input,
    controller,
    container,
    size,
    marquee,
    set_painted,
    hover_id,
    feedback.status,
    prepared,
    key,
    svg,
    canvas_visible,
    fn() { set_failed_canvas(Some(key)) },
  )
}

///|
let cached_stage : @core.Any = memo_component(stage)
