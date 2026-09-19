///|
pub fn inspector(_input : @core.Any) -> @react.Element {
  let editor = use_editor()
  let scene = editor._get("scene")
  let store = editor._get("store")
  let scene_id : String = scene._get("id").cast()
  let composition_id : String = editor._get("compositionId").cast()
  let selected : FixedArray[String] = editor._get("selectedIds").cast()
  let controller : InspectorController = {
    editor,
    scene,
    store,
    scene_id,
    composition_id,
    selected,
  }
  let selection = editor._get("selection")
  let object = if selected.length() == 1 {
    scene._get("objects")._get(selected[0])
  } else {
    @core.undefined()
  }
  let transition = if selection._get("kind").cast() == "transition" {
    scene._get("transitions")._get(selection._get("id").cast())
  } else {
    @core.undefined()
  }
  let locked = selected
    .iter()
    .any(fn(id) {
      let object = scene._get("objects")._get(id)
      truthy(object) && truthy(object._get("locked"))
    })
  if truthy(transition) && selected.length() > 1 {
    return h("div", { "className": @core.any("inspector-content") }, [
      h("div", { "className": @core.any("inspector-title") }, [
        h("span", Map([]), ["\{selected.length()} objects"]),
        h("span", { "className": @core.any("inspector-kind") }, [
          "Transition · " + string_value(transition._get("duration")) + " ms",
        ]),
      ]),
      component(group_controls, Map([]), []),
      component(group_animation_inspector, Map([]), []),
    ])
  }
  let title = if truthy(transition) {
    if truthy(object) && truthy(object._get("name")) {
      string_value(object._get("name"))
    } else {
      "Transition"
    }
  } else if selected.length() > 1 {
    "\{selected.length()} objects"
  } else if truthy(object) {
    @editor.object_label(@boundary.read_object_kind(object._get("kind")))
  } else {
    "Composition"
  }
  let labels : Array[&@react.ReactNode] = [h("span", Map([]), [title])]
  if truthy(object) {
    let object_id : String = object._get("id").cast()
    let locked = truthy(object._get("locked"))
    labels.push(
      component(
        icon_button,
        {
          "label": @core.any(
            if locked {
              "ロック解除"
            } else {
              "ロック"
            },
          ),
          "active": @core.any(locked),
          "onClick": @core.any(fn() {
            let current = store
              ._call("scene", [@core.any(scene_id)])
              ._get("objects")
              ._get(object_id)
            store._call("setObject", [
              @core.any(scene_id),
              @core.any(object_id),
              host_record({
                "locked": @core.any(
                  !(truthy(current) && truthy(current._get("locked"))),
                ),
              }),
            ])
            |> ignore
          }),
        },
        [icon(if locked { "LockKeyhole" } else { "UnlockKeyhole" }, 13)],
      ),
    )
  }
  let heading : Array[&@react.ReactNode] = [
    h("div", { "className": @core.any("inspector-title-label") }, labels),
  ]
  if truthy(transition) {
    heading.push(
      h("span", { "className": @core.any("inspector-kind") }, [
        if truthy(object) {
          @editor.object_label(@boundary.read_object_kind(object._get("kind")))
        } else {
          "Between compositions"
        },
      ]),
    )
  } else if truthy(object) {
    heading.push(
      h(
        "input",
        {
          "className": @core.any("object-name"),
          "aria-label": @core.any("Object name"),
          "disabled": object._get("locked"),
          "value": object._get("name"),
          "onChange": @core.any(fn(event : @core.Any) {
            if controller.can_edit() {
              store._call("setObject", [
                @core.any(scene_id),
                object._get("id"),
                host_record({ "name": event._get("target")._get("value") }),
              ])
              |> ignore
            }
          }),
        },
        [],
      ),
    )
  }
  let content : Array[&@react.ReactNode] = [
    h("div", { "className": @core.any("inspector-title") }, heading),
    component(group_controls, Map([]), []),
  ]
  if locked {
    content.push(
      h("p", { "className": @core.any("inspector-lock-note") }, [
        "ロック中のレイヤーを解除すると編集できます。",
      ]),
    )
  }
  let fields = if truthy(transition) {
    transition_inspector(controller, object, transition, locked)
  } else {
    composition_inspector(
      controller,
      object,
      scene._get("compositions")._get(composition_id),
    )
  }
  content.push(
    h(
      "fieldset",
      {
        "key": @core.any("fields"),
        "className": @core.any("inspector-fields"),
        "disabled": @core.any(locked),
      },
      fields,
    ),
  )
  h("div", { "className": @core.any("inspector-content") }, content)
}
