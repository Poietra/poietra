///|
fn timeline_tracks(
  editor : @core.Any,
  transition : @core.Any,
  start : Double,
  scene_time : Double,
  animations : FixedArray[@core.Any],
  feedback : @core.Any,
) -> @react.Element {
  let selected : FixedArray[String] = editor._get("selectedIds").cast()
  let selected_track = animations
    .iter()
    .find_first(fn(item) {
      let id : String = item._get("object")._get("id").cast()
      selected.iter().any(fn(chosen) { chosen == id })
    })
  let idle = match selected_track {
    Some(item) => {
      let locked = truthy(item._get("object")._get("locked"))
      host_record({
        "kind": @core.any(if locked { "locked" } else { "idle" }),
        "label": item._get("object")._get("name"),
        "detail": @core.any(
          if locked {
            "ロック中 · 選択のみ"
          } else if truthy(editor._get("playing")) {
            "再生中 · 編集は停止後"
          } else {
            track_detail(
              item._get("track")._get("start").cast(),
              item._get("track")._get("duration").cast(),
            )
          },
        ),
      })
    }
    None =>
      host_record({
        "kind": @core.any("idle"),
        "label": @core.any("バーを選択して時間を調整"),
        "detail": @core.any("両端をドラッグで長さを変更"),
      })
  }
  let status = feedback._get("feedback")
  let active = if truthy(status) &&
    status._get("kind").cast() == "active" &&
    selected.length() > 0 {
    @core.any(selected[0])
  } else {
    @core.null()
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
    let track = item._get("track")
    let id : String = track._get("objectId").cast()
    rows.push(
      component(
        track_row,
        {
          "key": @core.any("object/" + id),
          "track": track,
          "report": feedback._get("report"),
          "active": active,
        },
        [],
      ),
    )
    for
      channel in [
        "position", "opacity", "size", "rotation", "fill", "stroke", "strokeWidth",
        "fontSize", "cornerRadius", "path", "reveal",
      ] {
      if @boundary.has_property_timing(track, channel) {
        rows.push(
          component(
            track_row,
            {
              "key": @core.any("property/" + id + "/" + channel),
              "track": track,
              "channel": @core.any(channel),
              "report": feedback._get("report"),
              "active": active,
            },
            [],
          ),
        )
      }
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
    h(
      "div",
      {
        "className": @core.any("track-playhead"),
        "key": @core.any("playhead"),
        "style": host_record({
          "left": @core.any(
            "calc(var(--track-label-width, 190px) + (100% - var(--track-label-width, 190px)) * " +
            string_value(@core.any(timeline_fraction(scene_time, duration))) +
            ")",
          ),
        }),
      },
      [],
    ),
  )
  h("div", { "className": @core.any("transition-tracks") }, [
    h("div", { "className": @core.any("transition-caption") }, [
      h("span", Map([]), ["Transition"]),
      h("span", Map([]), [@boundary.format_milliseconds(duration) + " ms"]),
      component(
        operation_feedback,
        {
          "status": if truthy(status) {
            status
          } else {
            idle
          },
          "className": @core.any("timeline-feedback"),
        },
        [],
      ),
      h(
        "button",
        {
          "aria-label": @core.any("Composition に戻る"),
          "onClick": @core.any(fn() {
            editor
            ._get("select")
            ._invoke([
              host_record({
                "kind": @core.any("composition"),
                "id": transition._get("toId"),
              }),
            ])
            |> ignore
          }),
        },
        [icon("ChevronDown", 14)],
      ),
    ]),
    component(
      transition_ruler,
      {
        "duration": @core.any(duration),
        "local": @core.any(scene_time),
        "start": @core.any(start),
      },
      [],
    ),
    h("div", { "className": @core.any("track-rows") }, rows),
  ])
}

///|
pub fn timeline(input : @core.Any) -> @react.Element {
  let editor = use_editor()
  let scene = editor._get("scene")
  let selection = editor._get("selection")
  let selected_id : String = selection._get("id").cast()
  let scene_id : String = scene._get("id").cast()
  let playhead : Double = editor._get("playhead").cast()
  // The playback clock does not rebuild structural timelines or target lists.
  let segments : FixedArray[@core.Any] = @react.use_memo(
    fn() { @boundary.scene_segments(scene).cast() },
    [scene],
  )
  let total = @react.use_memo(fn() { @boundary.scene_duration(scene) }, [scene])
  let transition = if selection._get("kind").cast() == "transition" &&
    !truthy(editor._get("viewingPlayback")) {
    scene._get("transitions")._get(selected_id)
  } else {
    @core.undefined()
  }
  let animations : FixedArray[@core.Any] = @react.use_memo(
    fn() {
      if truthy(transition) {
        @boundary.visible_animations(scene, transition)
      } else {
        []
      }
    },
    [scene, transition],
  )
  let feedback = use_operation_feedback(scene_id + ":" + selected_id)
  let cards : Array[&@react.ReactNode] = []
  for part in segments {
    let id : String = part._get("id").cast()
    let kind : String = part._get("kind").cast()
    let duration : Double = part._get("duration").cast()
    let composition = if kind == "composition" {
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
            editor
            ._get("select")
            ._invoke([
              host_record({ "kind": @core.any(kind), "id": @core.any(id) }),
            ])
            |> ignore
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
        "onClick": editor._get("appendComposition"),
      },
      [icon("Plus", 21)],
    ),
  )
  let content : Array[&@react.ReactNode] = [
    h("div", { "className": @core.any("composition-strip") }, cards),
  ]
  if truthy(transition) {
    let part = segments
      .iter()
      .find_first(fn(part) { part._get("id").cast() == selected_id })
    let start : Double = part
      .map(fn(part) { part._get("start").cast() })
      .unwrap_or(0.0)
    let duration : Double = transition._get("duration").cast()
    let scene_time = @scene.clamp(playhead - start, 0.0, duration)
    content.push(
      timeline_tracks(
        editor, transition, start, scene_time, animations, feedback,
      ),
    )
  } else {
    content.push(scene_ruler(editor, segments, total, playhead))
  }
  content.push(children(input))
  content.push(timeline_transport(input, editor, total))
  h(
    "section",
    {
      "className": @core.any(
        "timeline " + (if truthy(transition) { "expanded" } else { "" }),
      ),
      "aria-label": @core.any("タイムライン"),
    },
    content,
  )
}
