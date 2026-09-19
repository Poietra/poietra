///|
pub fn stage(input : @core.Any) -> @react.Element {
  let editor = use_editor()
  let scene = editor._get("scene")
  let store = editor._get("store")
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
  let tool_name : String = editor._get("tool").cast()
  let tool = if tool_name == "select" {
    @editor.SelectTool
  } else {
    @editor.DrawTool(@scene.object_kind(tool_name).unwrap())
  }
  let playing = truthy(editor._get("playing"))
  let can_edit = interactive && !playing
  let renderer = editor._get("renderer")
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
  let (hover_id, set_hover_id) = @react.use_state("")
  let feedback = use_operation_feedback(
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
  let prepared = use_prepared_stage_frame(drawn_frame, renderer, key)
  let factory = editor._get("createFramePainter")
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
    prepared._get("frame")
  }
  let svg : String = @react.use_memo(
    fn() {
      renderer
      ._call("frameToSvg", [
        displayed,
        host_record({ "idPrefix": @core.any(prefix) }),
      ])
      .cast()
    },
    [displayed, renderer, @core.any(prefix)],
  )
  let selected : FixedArray[String] = editor._get("selectedIds").cast()
  let controller : StageController = {
    editor,
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
    report: feedback._get("report").cast(),
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
    feedback._get("feedback"),
    prepared,
    key,
    svg,
    canvas_visible,
  )
}
