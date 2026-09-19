///|
fn stage_view(
  input : @core.Any,
  controller : StageController,
  container : @react.ReactRef[@core.Any],
  size : @exporting.Size,
  marquee : @geometry.Rectangle?,
  on_present : (StagePresentation?) -> Unit,
  hover_id : String,
  feedback : @core.Any,
  prepared : @core.Any,
  key : String,
  svg : String,
  canvas_visible : Bool,
) -> @react.Element {
  let objects : FixedArray[@core.Any] = controller.frame._get("objects").cast()
  let selection = objects
    .iter()
    .filter(fn(item) {
      let id : String = item._get("object")._get("id").cast()
      let opacity : Double = item._get("state")._get("opacity").cast()
      let progress : Double = item._get("writeProgress").cast()
      controller.selected.iter().any(fn(chosen) { chosen == id }) &&
      truthy(item._get("state")._get("visible")) &&
      opacity > 0.0 &&
      progress > 0.0
    })
    .to_array()
  let hovered = if controller.can_edit &&
    controller.tool is SelectTool &&
    controller.gesture.get_current() is None {
    objects
    .iter()
    .find_first(fn(item) { item._get("object")._get("id").cast() == hover_id })
  } else {
    None
  }
  let idle_object = match hovered {
    Some(item) => Some(item._get("object"))
    None =>
      if selection.length() == 1 {
        Some(selection[0]._get("object"))
      } else {
        None
      }
  }
  let idle_locked = idle_object
    .map(fn(object) {
      stage_object_locked(controller.scene, object._get("id").cast())
    })
    .unwrap_or(false)
  let idle = if idle_object is Some(object) {
    let kind = @boundary.read_object_kind(object._get("kind"))
    let detail = if idle_locked {
      "ロック中 · 選択のみ"
    } else if !controller.state_editing {
      "プレビュー · 選択のみ"
    } else if kind is Text || kind is Equation {
      "ダブルクリックで編集"
    } else {
      "ドラッグで移動"
    }
    encode_status(
      Some({
        kind: if idle_locked {
          @editor.Locked
        } else {
          @editor.Inactive
        },
        label: object._get("name").cast(),
        detail: Some(detail),
      }),
    )
  } else if selection.length() > 1 {
    encode_status(
      Some({
        kind: @editor.Inactive,
        label: "\{selection.length()} 個を選択",
        detail: Some("Shift で選択を追加・解除"),
      }),
    )
  } else {
    @core.null()
  }
  let factory = controller.editor._get("createFramePainter")
  let content : Array[&@react.ReactNode] = []
  if truthy(factory) {
    content.push(
      component(
        canvas_frame,
        {
          "key": @core.any("canvas"),
          "frame": prepared._get("frame"),
          "scene": controller.scene,
          "renderer": controller.renderer,
          "createFramePainter": factory,
          "presentationKey": @core.any(key),
          "width": @core.any(size.width),
          "height": @core.any(size.height),
          "visible": @core.any(canvas_visible),
          "onPresent": @core.any(fn(value : @core.Any) {
            on_present(
              if @core.is_nullish(value) {
                None
              } else {
                Some({
                  key: value._get("key").cast(),
                  width: value._get("width").cast(),
                  height: value._get("height").cast(),
                  frame: value._get("frame"),
                })
              },
            )
          }),
        },
        [],
      ),
    )
  }
  content.push(
    h(
      "div",
      {
        "key": @core.any("svg"),
        "className": classes([
          @core.any("scene-svg"),
          @core.any(if canvas_visible { "scene-hit-svg" } else { "" }),
        ]),
        "dangerouslySetInnerHTML": host_record({ "__html": @core.any(svg) }),
      },
      [],
    ),
  )
  content.push(stage_overlay(controller, selection, hovered, marquee))
  let active = truthy(feedback) && feedback._get("kind").cast() == "active"
  let cancelled = truthy(feedback) &&
    feedback._get("kind").cast() == "cancelled"
  if controller.can_edit {
    content.push(
      component(
        operation_feedback,
        {
          "status": if idle_locked && !active && !cancelled {
            idle
          } else if truthy(feedback) {
            feedback
          } else {
            idle
          },
          "className": @core.any("stage-feedback"),
        },
        [],
      ),
    )
  }
  if truthy(prepared._get("error")) || !truthy(prepared._get("ready")) {
    let error = truthy(prepared._get("error"))
    content.push(
      h(
        "div",
        {
          "className": @core.any("stage-media-status"),
          "role": @core.any(if error { "alert" } else { "status" }),
        },
        [
          if error {
            "動画フレームを読み込めませんでした"
          } else {
            "動画フレームを準備中"
          },
        ],
      ),
    )
  }
  let composition = controller.scene
    ._get("compositions")
    ._get(controller.composition_id)
  let name = if truthy(composition) && truthy(composition._get("name")) {
    string_value(composition._get("name"))
  } else {
    "Composition"
  }
  let mode = if active && controller.gesture.get_current() is Some(current) {
    @core.any(
      match current.mode {
        TransformObject(_, transform, _, _, _) =>
          @editor.stage_transform_name(transform)
        EditPath(_, _, _) => "path"
        DrawObject(_) => "draw"
        SelectArea(_) => "marquee"
        MoveObjects(_) => "move"
      },
    )
  } else {
    @core.undefined()
  }
  let prefix = optional_string(input._get("prefix")).unwrap_or("main")
  h(
    "div",
    { "className": @core.any("stage-container"), "ref": container.as_any() },
    [
      h(
        "div",
        {
          "ref": controller.surface.as_any(),
          "tabIndex": @core.any(-1),
          "aria-label": @core.any(name + " のキャンバス"),
          "className": classes([
            @core.any("stage-surface"),
            @core.any(
              if controller.tool is DrawTool(_) &&
                controller.can_edit &&
                controller.state_editing {
                "drawing"
              } else {
                ""
              },
            ),
            @core.any(if active { "is-manipulating" } else { "" }),
          ]),
          "data-gesture": mode,
          "style": host_record({
            "width": @core.any(size.width),
            "height": @core.any(size.height),
          }),
          "onPointerDown": @core.any(fn(event : @core.Any) {
            controller.down(event)
          }),
          "onPointerMove": @core.any(fn(event : @core.Any) {
            controller.pointer_move(event)
          }),
          "onPointerUp": @core.any(fn(event : @core.Any) {
            controller.up(event)
          }),
          "onDoubleClick": @core.any(fn(event : @core.Any) {
            controller.double_click(event)
          }),
          "onPointerCancel": @core.any(fn() { controller.finish(true) }),
          "onLostPointerCapture": @core.any(fn() { controller.finish(true) }),
          "onPointerLeave": @core.any(fn() {
            if controller.gesture.get_current() is None {
              controller.store._call("presence", [
                host_record({ "cursor": @core.null() }),
              ])
              |> ignore
              (controller.hover)(None)
              if controller.surface.get_current() is Some(element) {
                element._get("style")._set("cursor", @core.any(""))
              }
            }
          }),
          "data-testid": @core.any("stage-" + prefix),
        },
        content,
      ),
    ],
  )
}
