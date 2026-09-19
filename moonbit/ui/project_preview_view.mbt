///|
priv struct ProjectPreviewView {
  timeline : PreviewTimeline
  scene : @core.Any
  first : @core.Any?
  frame : @core.Any?
  display_frame : @core.Any?
  key : String
  ready : Bool
  canvas_visible : Bool
  size : @exporting.Size
  svg : String
  time : Double
  playing : Bool
  error : String
}

///|
fn project_playback_view(
  input : @core.Any,
  view : ProjectPreviewView,
  viewport : @react.ReactRef[@core.Any],
  on_present : (CanvasPresentation?) -> Unit,
  seek : (Double) -> Unit,
  toggle : () -> Unit,
  edit : () -> Unit,
) -> @react.Element {
  let factory = input._get("createFramePainter")
  let scene_id = if truthy(view.scene) {
    view.scene._get("id")
  } else {
    @core.undefined()
  }
  let stage : Array[&@react.ReactNode] = []
  if truthy(view.scene) && view.display_frame is Some(frame) && truthy(factory) {
    stage.push(
      component(
        canvas_frame,
        {
          "frame": frame,
          "scene": view.scene,
          "renderer": input._get("renderer"),
          "createFramePainter": factory,
          "presentationKey": @core.any(view.key),
          "width": @core.any(view.size.width),
          "height": @core.any(view.size.height),
          "visible": @core.any(view.canvas_visible),
          "onPresent": @core.any(fn(value : @core.Any) {
            if @core.is_nullish(value) {
              on_present(None)
            } else {
              on_present(
                Some({
                  key: value._get("key").cast(),
                  width: value._get("width").cast(),
                  height: value._get("height").cast(),
                }),
              )
            }
          }),
        },
        [],
      ),
    )
  }
  if view.frame is Some(_) && view.ready {
    stage.push(
      h(
        "div",
        {
          "className": @core.any("project-preview-svg"),
          "style": @core.from_entries([
            (
              "visibility",
              @core.any(if view.canvas_visible { "hidden" } else { "visible" }),
            ),
          ]),
          "dangerouslySetInnerHTML": @core.from_entries([
            ("__html", @core.any(view.svg)),
          ]),
        },
        [],
      ),
    )
  }
  if !view.ready && view.error.is_empty() {
    stage.push(
      h(
        "div",
        {
          "className": @core.any("project-preview-loading"),
          "role": @core.any("status"),
        },
        [
          icon("LoaderCircle", 20, props={
            "className": @core.any("loading-spinner"),
          }),
          "Scene を準備しています…",
        ],
      ),
    )
  }
  let aspect = view.first
    .map(fn(scene) {
      string_value(scene._get("width")) +
      " / " +
      string_value(scene._get("height"))
    })
    .unwrap_or("16 / 9")
  let nodes : Array[&@react.ReactNode] = [
    h(
      "div",
      {
        "ref": viewport.as_any(),
        "className": @core.any("project-preview-frame"),
        "data-testid": @core.any("project-preview-frame"),
        "data-scene-id": scene_id,
        "style": @core.from_entries([
          ("aspectRatio", @core.any(aspect)),
          (
            "background",
            view.frame
            .map(fn(frame) { frame._get("background") })
            .unwrap_or(@core.undefined()),
          ),
        ]),
      },
      stage,
    ),
  ]
  if !view.error.is_empty() {
    nodes.push(
      h(
        "p",
        { "role": @core.any("alert"), "className": @core.any("inline-error") },
        [view.error],
      ),
    )
  }
  nodes.push(
    h("div", { "className": @core.any("project-preview-transport") }, [
      h(
        "button",
        {
          "className": @core.any("subtle-button"),
          "aria-label": @core.any(
            if view.playing {
              "プロジェクトの再生を停止"
            } else {
              "プロジェクトを再生"
            },
          ),
          "onClick": @core.any(toggle),
          "disabled": @core.any(
            !view.playing &&
            (
              view.timeline.duration <= 0.0 ||
              !view.error.is_empty() ||
              !view.ready
            ),
          ),
        },
        [icon(if view.playing { "Pause" } else { "Play" }, 15)],
      ),
      h(
        "button",
        {
          "className": @core.any("icon-button"),
          "aria-label": @core.any("プロジェクトの先頭へ"),
          "onClick": @core.any(fn() { seek(0.0) }),
        },
        [icon("RotateCcw", 15)],
      ),
      h(
        "input",
        {
          "type": @core.any("range"),
          "aria-label": @core.any("Project preview position"),
          "min": @core.any(0),
          "max": @core.any(view.timeline.duration),
          "step": @core.any(1),
          "value": @core.any(view.time),
          "disabled": @core.any(view.timeline.duration <= 0.0),
          "onChange": @core.any(fn(event : @core.Any) {
            seek(number_value(event._get("target")._get("value").cast()))
          }),
        },
        [],
      ),
      h("span", Map([]), [
        fixed_number(view.time / 1000.0, 2) +
        " / " +
        fixed_number(view.timeline.duration / 1000.0, 2) +
        " s",
      ]),
    ]),
  )
  let scenes : Array[&@react.ReactNode] = []
  for segment in view.timeline.segments {
    scenes.push(
      h(
        "button",
        {
          "key": segment.scene._get("id"),
          "aria-current": if @core.equal(segment.scene._get("id"), scene_id) {
            @core.any("step")
          } else {
            @core.undefined()
          },
          "className": @core.any("subtle-button"),
          "onClick": @core.any(fn() { seek(segment.start) }),
        },
        [
          h("span", Map([]), [HostNode::{ value: segment.scene._get("name"), }]),
          h("small", Map([]), [
            fixed_number(segment.duration / 1000.0, 2) + " s",
          ]),
        ],
      ),
    )
  }
  nodes.push(
    h(
      "div",
      {
        "className": @core.any("project-preview-scenes"),
        "aria-label": @core.any("プロジェクトの場面"),
      },
      scenes,
    ),
  )
  let name = if truthy(view.scene) {
    string_value(view.scene._get("name"))
  } else {
    ""
  }
  nodes.push(
    h("div", { "className": @core.any("project-preview-footer") }, [
      h("span", Map([]), [
        name + " · \{view.timeline.segments.length()} scenes",
      ]),
      h(
        "button",
        {
          "className": @core.any("subtle-button"),
          "onClick": @core.any(edit),
          "disabled": @core.any(!truthy(view.scene)),
        },
        [icon("PencilLine", 14), "この場面を編集"],
      ),
    ]),
  )
  @react.fragment(nodes)
}

///|
pub fn project_preview(input : @core.Any) -> @react.Element {
  let nodes : Array[&@react.ReactNode] = []
  if truthy(input._get("open")) {
    nodes.push(component(project_playback, props_except(input, []), []))
  }
  component(
    modal,
    {
      "open": input._get("open"),
      "onOpenChange": input._get("onOpenChange"),
      "title": @core.any("Project preview"),
      "description": input._get("project")._get("name"),
      "className": @core.any("project-preview-dialog"),
    },
    nodes,
  )
}
