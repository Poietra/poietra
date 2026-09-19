///|
fn timeline_fraction(value : Double, duration : Double) -> Double {
  if duration > 0.0 {
    @scene.clamp(value / duration, 0.0, 1.0)
  } else {
    0.0
  }
}

///|
fn track_row(input : @core.Any) -> @react.Element {
  let editor = use_editor()
  let scene = editor._get("scene")
  let store = editor._get("store")
  let scene_id : String = scene._get("id").cast()
  let transition_id : String = editor._get("selection")._get("id").cast()
  let track = input._get("track")
  let object_id : String = track._get("objectId").cast()
  let transition = scene._get("transitions")._get(transition_id)
  let object = scene._get("objects")._get(object_id)
  let lane = @react.use_ref((None : @core.Any?))
  let drag = @react.use_ref((None : TrackGesture?))
  let channel = if @core.is_undefined(input._get("channel")) {
    None
  } else {
    @scene.property_channel(input._get("channel").cast())
  }
  let label = match channel {
    Some(channel) => @editor.property_channel_label(channel)
    None => animation_label(track._get("type"))
  }
  let playing = truthy(editor._get("playing"))
  let locked = truthy(object) && truthy(object._get("locked"))
  let controller : TrackController = {
    store,
    scene_id,
    transition_id,
    object_id,
    object_name: if truthy(object) {
      object._get("name").cast()
    } else {
      ""
    },
    label,
    channel,
    lane,
    drag,
    report: input._get("report").cast(),
    select: editor._get("setSelectedIds").cast(),
    notify: editor._get("notify").cast(),
    playing,
  }
  let total : Double = if truthy(transition) {
    transition._get("duration").cast()
  } else {
    0.0
  }
  @react.use_effect(
    fn() {
      let window = @core.global_this()._get("window")
      let key = fn(event : @core.Any) {
        if event._get("key").cast() == "Escape" && drag.get_current() is Some(_) {
          prevent_default(event)
          event._call("stopImmediatePropagation", []) |> ignore
          controller.finish(true)
        }
      }
      let cancel = fn() { controller.finish(true) }
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
      @core.any(transition_id),
      @core.any(object_id),
      input._get("channel"),
      @core.any(total),
      @core.any(locked),
      @core.any(playing),
      store,
    ],
  )
  if !truthy(object) || !truthy(transition) {
    return @react.fragment([])
  }
  let timing = controller.timing(track)
  let selected : FixedArray[String] = editor._get("selectedIds").cast()
  let chosen = selected.iter().any(fn(id) { id == object_id })
  let disabled = locked || playing || total <= 0.0
  let reason = if locked {
    "ロック中のため時間は変更できません"
  } else if playing {
    "再生を停止すると時間を変更できます"
  } else if total <= 0.0 {
    "Transition の長さを設定すると時間を変更できます"
  } else {
    "ドラッグで移動、両端で開始・終了を調整。選択すると右側でも時間を入力できます"
  }
  let labels : Array[&@react.ReactNode] = [
    if channel is Some(_) {
      icon("CornerDownRight", 12)
    } else {
      component(object_icon, { "kind": object._get("kind") }, [])
    },
    h("span", Map([]), [
      if channel is Some(_) {
        label
      } else {
        controller.object_name
      },
    ]),
  ]
  if locked {
    labels.push(
      icon("LockKeyhole", 12, props={ "aria-label": @core.any("ロック中") }),
    )
  }
  if channel is None {
    labels.push(h("small", Map([]), [label]))
  }
  let label_button = h(
    "button",
    {
      "className": @core.any("track-label"),
      "aria-label": if channel is Some(_) {
        @core.any(controller.object_name + " " + label)
      } else {
        @core.undefined()
      },
      "aria-pressed": @core.any(chosen),
      "onClick": @core.any(fn() {
        (controller.report)(@core.null())
        (controller.select)([object_id])
      }),
    },
    labels,
  )
  let left = timeline_fraction(timing.start, total) * 100.0
  let width = timeline_fraction(
      timing.duration.min((total - timing.start).max(0.0)),
      total,
    ) *
    100.0
  let bar = h(
    "button",
    {
      "className": classes([
        @core.any("animation-bar"),
        @core.any(if chosen { "selected" } else { "" }),
      ]),
      "style": host_record({
        "left": @core.any(
          "min(" + string_value(@core.any(left)) + "%, calc(100% - 6px))",
        ),
        "width": @core.any("max(6px, " + string_value(@core.any(width)) + "%)"),
        "cursor": if disabled {
          @core.any("not-allowed")
        } else {
          @core.undefined()
        },
      }),
      "aria-label": @core.any(
        controller.object_name +
        " " +
        label +
        ": " +
        track_detail(timing.start, timing.duration),
      ),
      "aria-disabled": @core.any(disabled),
      "aria-pressed": @core.any(chosen),
      "title": @core.any(reason),
      "aria-description": @core.any(reason),
      "onPointerDown": @core.any(fn(event : @core.Any) {
        controller.down(event)
      }),
      "onPointerMove": @core.any(fn(event : @core.Any) {
        controller.pointer_move(event)
      }),
      "onPointerUp": @core.any(fn(event : @core.Any) {
        controller.end(event, false)
      }),
      "onPointerCancel": @core.any(fn(event : @core.Any) {
        controller.end(event, true)
      }),
      "onLostPointerCapture": @core.any(fn(event : @core.Any) {
        controller.end(event, true)
      }),
      "onClick": @core.any(fn() { (controller.select)([object_id]) }),
    },
    [
      h(
        "span",
        {
          "data-edge": @core.any("start"),
          "className": @core.any("bar-handle start"),
        },
        [],
      ),
      h("span", { "className": @core.any("bar-name") }, [
        label,
        h("span", { "className": @core.any("bar-timing") }, [
          " · " + track_detail(timing.start, timing.duration),
        ]),
      ]),
      h(
        "span",
        {
          "data-edge": @core.any("end"),
          "className": @core.any("bar-handle end"),
        },
        [],
      ),
    ],
  )
  h(
    "div",
    {
      "data-track-object-id": if channel is None {
        @core.any(object_id)
      } else {
        @core.undefined()
      },
      "data-property-object-id": if channel is Some(_) {
        @core.any(object_id)
      } else {
        @core.undefined()
      },
      "data-property-channel": input._get("channel"),
      "data-track-active": if @core.equal(
          input._get("active"),
          @core.any(object_id),
        ) {
        @core.any(true)
      } else {
        @core.undefined()
      },
      "className": classes([
        @core.any("track-row"),
        @core.any(if channel is Some(_) { "property-track-row" } else { "" }),
        @core.any(if chosen { "selected" } else { "" }),
        @core.any(if disabled { "track-unavailable" } else { "" }),
      ]),
    },
    [
      label_button,
      h("div", { "className": @core.any("track-lane"), "ref": lane.as_any() }, [
        bar,
      ]),
    ],
  )
}
