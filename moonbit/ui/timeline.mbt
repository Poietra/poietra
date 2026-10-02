///|
fn timeline_tracks(
  editor : EditorView,
  transition : @core.Any,
  start : Double,
  animations : Array[TrackRowData],
  feedback : OperationFeedback,
) -> @react.Element {
  let selected : FixedArray[String] = editor.selected_ids
  let selected_track = animations
    .iter()
    .find_first(fn(item) {
      selected
      .iter()
      .any(fn(chosen) { chosen == item.binding.target.object_id })
    })
  let idle : @editor.OperationStatus = match selected_track {
    Some(item) =>
      {
        kind: if item.locked {
          Locked
        } else {
          Inactive
        },
        label: item.object_name,
        detail: Some(
          if item.locked {
            "ロック中 · 選択のみ"
          } else if editor.playing {
            "再生中 · 編集は停止後"
          } else {
            track_detail(item.timing.start, item.timing.duration)
          },
        ),
      }
    None =>
      {
        kind: Inactive,
        label: "バーを選択して時間を調整",
        detail: Some("両端をドラッグで長さを変更"),
      }
  }
  let status = feedback.status
  let active = if status is Some(status) &&
    status.kind == Active &&
    selected.length() > 0 {
    Some(selected[0])
  } else {
    None
  }
  let duration : Double = transition._get("duration").cast()
  let marks : Array[&@react.ReactNode] = []
  for index = 0; index < 5; index = index + 1 {
    marks.push(
      h(
        "i",
        {
          "key": @core.any(index),
          "style": host_record({ "left": @core.any("\{index * 25}%") }),
        },
        [],
      ),
    )
  }
  let rows : Array[&@react.ReactNode] = [
    h(
      "div",
      { "className": @core.any("track-grid"), "key": @core.any("grid") },
      marks,
    ),
  ]
  for item in animations {
    let id = item.binding.target.object_id
    rows.push(
      typed_component(
        track_row_component,
        {
          data: item,
          timing: item.timing,
          channel: None,
          report: feedback.report,
          active: active == Some(id),
        },
        key="object/" + id,
      ),
    )
    for (channel, timing) in item.properties {
      rows.push(
        typed_component(
          track_row_component,
          {
            data: item,
            timing,
            channel: Some(channel),
            report: feedback.report,
            active: active == Some(id),
          },
          key="property/" + id + "/" + @editor.property_channel_name(channel),
        ),
      )
    }
  }
  if animations.is_empty() {
    rows.push(
      h("p", { "className": @core.any("tracks-empty") }, [
        "Composition にオブジェクトを追加すると、動きを調整できます",
      ]),
    )
  }
  rows.push(
    component(
      timeline_playhead,
      {
        "key": @core.any("playhead"),
        "start": @core.any(start),
        "duration": @core.any(duration),
      },
      [],
    ),
  )
  h("div", { "className": @core.any("transition-tracks") }, [
    h("div", { "className": @core.any("transition-caption") }, [
      h("span", Map([]), ["Transition"]),
      h("span", Map([]), [@boundary.format_milliseconds(duration) + " ms"]),
      typed_component(operation_feedback_component, {
        status: Some(status.unwrap_or(idle)),
        class_name: Some("timeline-feedback"),
      }),
      h(
        "button",
        {
          "aria-label": @core.any("Composition に戻る"),
          "onClick": @core.any(fn() {
            (editor.actions.select)(
              CompositionSelection(transition._get("toId").cast()),
            )
          }),
        },
        [icon("ChevronDown", 14)],
      ),
    ]),
    component(
      transition_ruler,
      { "duration": @core.any(duration), "start": @core.any(start) },
      [],
    ),
    h("div", { "className": @core.any("track-rows") }, rows),
  ])
}

///|
pub fn timeline(input : @core.Any) -> @react.Element {
  let editor = use_editor_state()
  let scene = editor.scene
  let selection = editor.selection
  let expanded = selection is TransitionSelection(_) && !editor.viewing_playback
  let total = @boundary.scene_duration(scene)
  let dependencies = editor_presentation_inputs(editor)
  dependencies.append(composition_presentation_inputs(scene, true))
  dependencies.push(@core.any(total))
  let transitions = scene._get("transitions")
  let transition_ids = @core.object_keys(transitions)
  dependencies.push(@core.any(transition_ids.length()))
  for id in transition_ids {
    let transition = transitions._get(id)
    dependencies.append([
      @core.any(id),
      transition._get("fromId"),
      transition._get("toId"),
      transition._get("duration"),
    ])
  }
  if expanded {
    dependencies.push(scene._get("objects"))
    let transition = scene._get("transitions")._get(selection.id())
    if truthy(transition) {
      dependencies.push(transition._get("tracks"))
      for key in ["fromId", "toId"] {
        let cid : String = transition._get(key).cast()
        for id in @core.object_keys(scene._get("objects")) {
          let state = @boundary.state_for(scene, cid, id)
          dependencies.push(
            @core.any(truthy(state) && truthy(state._get("visible"))),
          )
        }
      }
    }
  }
  let props = use_presentation_props(dependencies, fn() { editor })
  h(
    "section",
    {
      "className": @core.any(
        "timeline " + (if expanded { "expanded" } else { "" }),
      ),
      "aria-label": @core.any("タイムライン"),
    },
    [
      typed_component(cached_timeline_structure, props),
      children(input),
      timeline_transport(input, editor, total),
    ],
  )
}

///|
let cached_timeline_structure : TypedComponent[EditorView] = memo_typed_component(
  timeline_structure,
)

///|
fn timeline_structure(editor : EditorView) -> @react.Element {
  let scene = editor.scene
  let selection = editor.selection
  let selected_id : String = selection.id()
  let scene_id : String = scene._get("id").cast()
  // The playback clock does not rebuild structural timelines or target lists.
  let segments : Array[@scene.Segment] = @react.use_memo(
    fn() { @boundary.read_scene_segments(scene) },
    [scene],
  )
  let total = @react.use_memo(fn() { @boundary.scene_duration(scene) }, [scene])
  let transition = if selection is TransitionSelection(_) &&
    !editor.viewing_playback {
    scene._get("transitions")._get(selected_id)
  } else {
    @core.undefined()
  }
  let animations : Array[TrackRowData] = @react.use_memo(
    fn() {
      if truthy(transition) {
        native_timeline_tracks(editor, transition)
      } else {
        []
      }
    },
    [scene, transition, editor.store],
  )
  let feedback = use_operation_feedback_state(scene_id + ":" + selected_id)
  let cards : Array[&@react.ReactNode] = []
  for part in segments {
    let id = part.id
    let kind = @scene.segment_kind_name(part.kind)
    let duration = part.duration
    let composition = if part.kind == @scene.CompositionSegment {
      scene._get("compositions")._get(id)
    } else {
      @core.undefined()
    }
    let name = if truthy(composition) && truthy(composition._get("name")) {
      string_value(composition._get("name"))
    } else {
      "Transition"
    }
    let title : Array[&@react.ReactNode] = [
      h(
        "span",
        {
          "className": @core.any(
            if truthy(composition) {
              "composition-symbol"
            } else {
              "transition-symbol"
            },
          ),
        },
        [
          icon(
            if truthy(composition) {
              "Square"
            } else {
              "ArrowRight"
            },
            if truthy(composition) {
              8
            } else {
              10
            },
          ),
        ],
      ),
      h("span", Map([]), [name]),
    ]
    title.push(
      if truthy(composition) {
        h(
          "i",
          { "style": host_record({ "background": composition._get("accent") }) },
          [],
        )
      } else {
        icon("ChevronDown", 12)
      },
    )
    cards.push(
      h(
        "button",
        {
          "key": @core.any("object/" + id),
          "className": @core.any(
            "segment-card " +
            kind +
            " " +
            (if selected_id == id { "selected" } else { "" }),
          ),
          "style": host_record({ "flexGrow": @core.any(duration.max(500.0)) }),
          "onClick": @core.any(fn() {
            (editor.actions.select)(segment_selection(part))
          }),
          "aria-label": @core.any(
            name + " " + @boundary.format_milliseconds(duration) + " ms",
          ),
          "aria-pressed": @core.any(selected_id == id),
        },
        [
          h("span", { "className": @core.any("segment-title") }, title),
          h("span", { "className": @core.any("segment-duration") }, [
            @boundary.format_milliseconds(duration) + " ms",
          ]),
        ],
      ),
    )
  }
  cards.push(
    h(
      "button",
      {
        "key": @core.any("add"),
        "className": @core.any("add-composition"),
        "aria-label": @core.any("Composition を追加"),
        "onClick": @core.any(editor.actions.append_composition),
      },
      [icon("Plus", 21)],
    ),
  )
  let content : Array[&@react.ReactNode] = [
    h("div", { "className": @core.any("composition-strip") }, cards),
  ]
  if truthy(transition) {
    let part = segments.iter().find_first(fn(part) { part.id == selected_id })
    let start : Double = part.map(fn(part) { part.start }).unwrap_or(0.0)
    content.push(
      timeline_tracks(editor, transition, start, animations, feedback),
    )
  } else {
    content.push(
      component(
        scene_ruler,
        { "segments": @core.any(segments), "total": @core.any(total) },
        [],
      ),
    )
  }
  @react.fragment(content)
}
