///|
pub fn media_timeline(input : @core.Any) -> @react.Element {
  let editor = use_editor_state()
  let scene = editor._get("scene")
  let dependencies = editor_presentation_inputs(editor)
  dependencies.append([
    scene._get("objects"),
    scene._get("audioTracks"),
    @core.any(@boundary.scene_duration(scene)),
    input._get("disabled"),
  ])
  let add = use_latest_action(input._get("onAdd"))
  let props = use_presentation_props(dependencies, fn() {
    host_record({
      "editor": editor,
      "disabled": input._get("disabled"),
      "onAdd": add,
    })
  })
  keyed_element(cached_media_timeline_content, { "view": props }, [])
}

///|
let cached_media_timeline_content : @core.Any = memo_component(
  media_timeline_content,
)

///|
fn media_timeline_content(input : @core.Any) -> @react.Element {
  let input = input._get("view")
  let editor = input._get("editor")
  let scene = editor._get("scene")
  let scene_id : String = scene._get("id").cast()
  let store = editor._get("store")
  let playing = truthy(editor._get("playing"))
  let disabled = truthy(input._get("disabled"))
  let busy = playing || disabled
  let (selected, set_selected) = @react.use_state((None : String?))
  let (draft, set_draft) = @react.use_state((None : @scene.MediaPlayback?))
  let (message, set_message) = @react.use_state("")
  let controller : MediaController = @react.use_memo(
    fn() {
      {
        store,
        scene_id,
        select: set_selected,
        draft: set_draft,
        message: set_message,
        notify: editor._get("notify").cast(),
        selected_ids: editor._get("setSelectedIds").cast(),
        drag: None,
        busy,
      }
    },
    [store, @core.any(scene_id)],
  )
  controller.busy = busy
  @react.use_effect(
    fn() {
      let window = @core.global_this()._get("window")
      let cancel = fn() { controller.finish(true) }
      let key = fn(event : @core.Any) {
        if event._get("key").cast() == "Escape" && controller.drag is Some(_) {
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
    [@core.any(controller), @core.any(playing), @core.any(disabled)],
  )
  let clips = @react.use_memo(fn() { media_clips(scene) }, [
    scene._get("objects"),
    scene._get("audioTracks"),
  ])
  let current = clips.iter().find_first(fn(clip) { selected == Some(clip.id) })
  let total = @scene.maximum(
    @boundary.scene_duration(scene).max(1000.0),
    draft.map(fn(value) { value.start + value.duration }).unwrap_or(0.0),
  )
  let content : Array[&@react.ReactNode] = [
    h("div", { "className": @core.any("media-track-heading") }, [
      h("span", Map([]), [
        icon("Music2", 13),
        "Audio & video",
        h("span", { "className": @core.any("media-count") }, [
          if clips.is_empty() {
            ""
          } else {
            clips.length().to_string()
          },
        ]),
      ]),
      h("div", Map([]), [
        inspector_button(
          "音声を追加",
          "Plus",
          fn() { input._get("onAdd")._invoke([@core.any("audio")]) |> ignore },
          class_name="text-button",
          disabled=busy,
        ),
        inspector_button(
          "動画を追加",
          "Film",
          fn() { input._get("onAdd")._invoke([@core.any("video")]) |> ignore },
          class_name="text-button",
          disabled=busy,
        ),
      ]),
    ]),
  ]
  if clips.is_empty() {
    content.push(
      h("p", { "className": @core.any("media-empty") }, [
        "音声は独立トラックに。波形を見ながら位置や長さを調整できます。",
      ]),
    )
  } else {
    let marks : Array[&@react.ReactNode] = []
    for index = 0; index < 5; index = index + 1 {
      marks.push(
        h(
          "span",
          {
            "key": @core.any(index),
            "style": host_record({ "left": @core.any("\{index * 25}%") }),
          },
          [media_seconds(total * index.to_double() / 4.0)],
        ),
      )
    }
    marks.push(component(media_seek, { "total": @core.any(total) }, []))
    content.push(
      h("div", { "className": @core.any("media-track-ruler") }, [
        h("span", Map([]), ["Scene time"]),
        h("div", Map([]), marks),
      ]),
    )
    let lanes : Array[&@react.ReactNode] = []
    for clip in clips {
      let chosen = selected == Some(clip.id)
      let timing = if chosen {
        draft.unwrap_or(clip.timing)
      } else {
        clip.timing
      }
      lanes.push(media_lane(controller, clip, timing, chosen, total))
    }
    content.push(h("div", { "className": @core.any("media-lanes") }, lanes))
    if current is Some(clip) {
      content.push(media_properties(controller, clip))
    }
    let description = if !message.is_empty() {
      message
    } else if current is Some(clip) {
      (if clip.kind is AudioClip { "音声" } else { "動画" }) +
      " · " +
      media_seconds(clip.asset._get("duration").cast()) +
      " · " +
      (if clip.locked {
        "ロック中 · 選択のみ"
      } else {
        "ドラッグで移動、両端でトリミング"
      })
    } else {
      "クリップを選ぶと開始位置・長さ・音量を編集できます"
    }
    content.push(
      h(
        "div",
        {
          "className": @core.any("media-track-status"),
          "role": @core.any("status"),
          "aria-live": @core.any(
            if controller.drag is Some(_) {
              "off"
            } else {
              "polite"
            },
          ),
        },
        [description],
      ),
    )
  }
  h(
    "section",
    {
      "className": @core.any("media-timeline"),
      "aria-label": @core.any("音声・動画トラック"),
    },
    content,
  )
}

///|
fn media_seek(input : @core.Any) -> @react.Element {
  let editor = use_editor_state()
  let total : Double = input._get("total").cast()
  let playhead = use_editor_position(editor)
  h(
    "input",
    {
      "aria-label": @core.any("素材トラックの再生位置"),
      "type": @core.any("range"),
      "min": @core.any(0),
      "max": @core.any(total),
      "value": @core.any(playhead.min(total)),
      "step": @core.any(1),
      "onChange": @core.any(fn(event : @core.Any) {
        editor
        ._get("seek")
        ._invoke([
          @core.any(number_value(event._get("target")._get("value").cast())),
          @core.any("scene"),
        ])
        |> ignore
      }),
    },
    [],
  )
}
