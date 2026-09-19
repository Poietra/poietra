///|
fn animation_label(value : @core.Any) -> String {
  if @core.is_undefined(value) {
    return ""
  }
  match @scene.animation_kind(value.cast()) {
    Some(Move) => "Move"
    Some(Write) => "Write"
    Some(Fade) => "Fade"
    Some(Grow) => "Grow"
    Some(Cut) | None => "Cut"
  }
}

///|
pub fn group_animation_inspector(_input : @core.Any) -> @react.Element {
  let editor = use_editor()
  let selection = editor._get("selection")
  if selection._get("kind").cast() != "transition" {
    return @react.fragment([])
  }
  let scene = editor._get("scene")
  let scene_id : String = scene._get("id").cast()
  let transition_id : String = selection._get("id").cast()
  let transition = scene._get("transitions")._get(transition_id)
  if !truthy(transition) {
    return @react.fragment([])
  }
  let store = editor._get("store")
  let result = @boundary.group_animation_targets(
    scene,
    transition_id,
    editor._get("selectedIds").cast(),
  )
  let targets : FixedArray[@core.Any] = result._get("targets").cast()
  let excluded : FixedArray[@core.Any] = result._get("excluded").cast()
  let ids : FixedArray[String] = FixedArray::makei(targets.length(), fn(i) {
    targets[i]._get("object")._get("id").cast()
  })
  let target_key = "\{scene_id}/\{transition_id}/" + ids.iter().join(",")
  let timings = targets
    .iter()
    .map(fn(target) {
      @editor.GroupTiming::{
        existing: truthy(target._get("existing")),
        start: target._get("track")._get("start").cast(),
        duration: target._get("track")._get("duration").cast(),
      }
    })
    .to_array()
  let (maximum_start, maximum_duration) = @editor.group_timing_limits(
    timings,
    transition._get("duration").cast(),
  )
  let common_type = @boundary.common_track_value(targets, "type")
  let kind = if @core.is_undefined(common_type) {
    None
  } else {
    @scene.animation_kind(common_type.cast())
  }
  let viewing = truthy(editor._get("viewingPlayback"))
  let playing = truthy(editor._get("playing"))
  let apply = fn(key : String, value : @core.Any, separate : Bool) {
    if viewing {
      return
    }
    attempt(
      fn() {
        let patch = @core.new_object()
        patch._set(key, value)
        let changes = @boundary.group_animation_changes(
          store._call("scene", [@core.any(scene_id)]),
          transition_id,
          ids,
          patch,
        )
        if changes.length() > 0 {
          store._call("edit", [@core.any(changes), @core.any(separate)])
          |> ignore
        }
      },
      fn(message) {
        editor._get("notify")._invoke([@core.any(message)]) |> ignore
      },
      "アニメーションを変更できませんでした。",
    )
  }
  let content : Array[&@react.ReactNode] = [
    h("p", { "className": @core.any("group-animation-explanation") }, [
      "表示される選択メンバーに適用します。Enter は登場、Exit は退場の動きです。",
    ]),
  ]
  let members : Array[&@react.ReactNode] = []
  for target in targets {
    let presence : String = target._get("presence").cast()
    let prefix = match presence {
      "enter" => "Enter · "
      "exit" => "Exit · "
      _ => ""
    }
    members.push(
      h("li", { "key": target._get("object")._get("id") }, [
        h("span", Map([]), [string_value(target._get("object")._get("name"))]),
        h("small", Map([]), [
          prefix + animation_label(target._get("track")._get("type")),
        ]),
      ]),
    )
  }
  content.push(
    h(
      "ul",
      {
        "className": @core.any("group-animation-targets"),
        "aria-label": @core.any("Animation targets"),
      },
      members,
    ),
  )
  if excluded.length() > 0 {
    let members : Array[&@react.ReactNode] = []
    for target in excluded {
      let reason : String = target._get("reason").cast()
      members.push(
        h("li", { "key": target._get("object")._get("id") }, [
          h("span", Map([]), [string_value(target._get("object")._get("name"))]),
          h("small", Map([]), [
            if reason == "locked" {
              "ロック中"
            } else {
              "非表示"
            },
          ]),
        ]),
      )
    }
    content.push(
      h(
        "ul",
        {
          "className": @core.any("group-animation-excluded"),
          "aria-label": @core.any("Excluded animation targets"),
        },
        members,
      ),
    )
  }
  if targets.length() == 0 {
    content.push(
      h("p", { "className": @core.any("group-animation-explanation") }, [
        "対象がありません。ロックと表示状態を確認してください。",
      ]),
    )
  }
  let options : Array[&@react.ReactNode] = [
    export_choice("", "Mixed", disabled=true),
  ]
  for name in ["move", "write", "fade", "grow", "none"] {
    options.push(export_choice(name, animation_label(@core.any(name))))
  }
  let fields : Array[&@react.ReactNode] = [
    component(field, { "label": @core.any("Type") }, [
      h(
        "select",
        {
          "aria-label": @core.any("Selected animation type"),
          "value": if @core.is_undefined(common_type) {
            @core.any("")
          } else {
            common_type
          },
          "onChange": @core.any(fn(event : @core.Any) {
            apply("type", event._get("target")._get("value"), true)
          }),
        },
        options,
      ),
    ]),
  ]
  if kind == Some(@scene.Write) {
    let value = @boundary.common_track_value(targets, "order")
    fields.push(
      component(field, { "label": @core.any("Order") }, [
        h(
          "select",
          {
            "aria-label": @core.any("Selected Write order"),
            "value": if @core.is_undefined(value) {
              @core.any("")
            } else {
              value
            },
            "onChange": @core.any(fn(event : @core.Any) {
              apply("order", event._get("target")._get("value"), true)
            }),
          },
          [
            export_choice("", "Mixed", disabled=true),
            export_choice("together", "Together"),
            export_choice("sequential", "Sequential"),
          ],
        ),
      ]),
    )
  }
  for
    (key, label, maximum) in [
      ("start", "Start", maximum_start),
      ("duration", "Duration", maximum_duration),
    ] {
    fields.push(
      component(field, { "label": @core.any(label) }, [
        component(
          common_number,
          {
            "key": @core.any(target_key + "/" + key),
            "label": @core.any("Selected animation " + key),
            "value": @boundary.common_track_value(targets, key),
            "max": @core.any(maximum),
            "onCommit": @core.any(fn(value : Double) {
              apply(key, @core.any(value), true)
            }),
          },
          [],
        ),
      ]),
    )
  }
  fields.push(
    component(
      easing_editor,
      {
        "key": @core.any(target_key),
        "value": @boundary.common_track_value(targets, "easing"),
        "label": @core.any("Selected animation easing"),
        "onChange": @core.any(fn(value : @core.Any, separate : @core.Any) {
          apply(
            "easing",
            value,
            @core.is_undefined(separate) || truthy(separate),
          )
        }),
        "getValue": @core.any(fn() {
          let current = store._call("project", [])._get("scenes")._get(scene_id)
          if !truthy(current) {
            return @core.undefined()
          }
          @boundary.common_track_value(
            @boundary.group_animation_targets(current, transition_id, ids)
            ._get("targets")
            .cast(),
            "easing",
          )
        }),
        "disabled": @core.any(
          targets.length() == 0 ||
          viewing ||
          playing ||
          kind == Some(@scene.Cut),
        ),
        "disabledReason": if kind == Some(@scene.Cut) {
          @core.any(
            "Cut は瞬時に切り替わるため、イージングを使用しません。",
          )
        } else if playing {
          @core.any(
            "再生を停止すると、イージングを調整できます。",
          )
        } else {
          @core.undefined()
        },
      },
      [],
    ),
  )
  content.push(
    h(
      "fieldset",
      {
        "disabled": @core.any(targets.length() == 0 || viewing),
        "className": @core.any("group-animation-fields"),
      },
      fields,
    ),
  )
  content.push(
    h("p", { "className": @core.any("group-animation-explanation") }, [
      "変更した項目だけを反映します。位置・移動パス・プロパティごとの時間は、メンバーごとの設定を保ちます。",
    ]),
  )
  if kind == Some(@scene.Grow) &&
    targets.iter().any(fn(target) { target._get("presence").cast() == "both" }) {
    content.push(
      h("p", { "className": @core.any("group-animation-explanation") }, [
        "Grow の拡大・縮小は Enter / Exit に適用します。両側に表示するメンバーは各場面の大きさへ変化します。",
      ]),
    )
  }
  if maximum_start == 0.0 && targets.length() > 0 {
    content.push(
      h("p", { "className": @core.any("group-animation-explanation") }, [
        "開始を遅らせるには、先に長さを短くしてください。",
      ]),
    )
  }
  h("div", { "className": @core.any("group-animation-inspector") }, [
    component(
      section,
      { "title": @core.any("Animation · \{targets.length()} targets") },
      content,
    ),
  ])
}
