///|
priv struct KeyNudge {
  target : @editor.NudgeTarget
  store : @core.Any
}

///|
extern "js" fn closest_element(
  value : @core.Any,
  selector : String,
) -> @core.Any =
  #|(value, selector) => value instanceof Element ? value.closest(selector) : null

///|
fn shortcut_text_target(target : @core.Any) -> Bool {
  !@core.is_nullish(
    closest_element(
      target, "input, textarea, select, [contenteditable=\"true\"], [role=\"dialog\"], [role=\"menu\"], [role=\"menuitem\"]",
    ),
  )
}

///|
fn selected_page_text() -> Bool {
  let selection = @core.global_this()._call("getSelection", [])
  !@core.is_nullish(selection) &&
  !@core.equal(selection._call("toString", []), @core.any(""))
}

///|
fn finish_key_nudge(owner : @react.ReactRef[KeyNudge]) -> Unit {
  if owner.get_current() is Some(nudge) {
    owner.set_current(None)
    nudge.store._call("endGesture", []) |> ignore
  }
}

///|
fn key_visible(scene : @core.Any, composition : String, id : String) -> Bool {
  let comp = scene._get("compositions")._get(composition)
  if @core.is_nullish(comp) {
    return false
  }
  let state = comp._get("states")._get(id)
  !@core.is_nullish(state) && truthy(state._get("visible"))
}

///|
fn key_select_composition(input : EditorControls, id : String) -> Unit {
  (input.actions.select)(CompositionSelection(id))
}

///|
fn key_nudge(
  input : EditorControls,
  owner : @react.ReactRef[KeyNudge],
  dx : Int,
  dy : Int,
) -> Unit {
  let store = input.store
  let scene_id : String = input.scene._get("id").cast()
  let composition : String = input.composition_id
  let current = store._call("scene", [@core.any(scene_id)])
  let linked : FixedArray[String] = store
    ._call("linkedIds", [@core.any(scene_id), @core.any(input.active_ids)])
    .cast()
  let ids = linked
    .iter()
    .filter(fn(id) { key_visible(current, composition, id) })
    .to_array()
  if ids.is_empty() {
    return
  }
  let target : @editor.NudgeTarget = {
    scene: scene_id,
    composition,
    objects: ids,
  }
  if !owner
    .get_current()
    .map(fn(nudge) { @core.equal(nudge.store, store) && nudge.target == target })
    .unwrap_or(false) {
    finish_key_nudge(owner)
    store._call("beginGesture", []) |> ignore
    owner.set_current(Some({ target, store, }))
  }
  let starts = @core.new_object()
  let states = current._get("compositions")._get(composition)._get("states")
  for id in ids {
    let state = states._get(id)
    starts._set(id, host_record({ "x": state._get("x"), "y": state._get("y") }))
  }
  store._call("translate", [
    @core.any(scene_id),
    @core.any(composition),
    starts,
    @core.any(dx),
    @core.any(dy),
  ])
  |> ignore
  (input.actions.set_playing)(false)
  (input.actions.set_transport_view)(false)
  (input.actions.set_tool)(@editor.SelectTool)
  if input.has_transition {
    key_select_composition(input, composition)
  }
}

///|
fn editor_key(
  input : EditorControls,
  owner : @react.ReactRef[KeyNudge],
  event : @core.Any,
) -> Unit {
  if truthy(event._get("defaultPrevented")) ||
    truthy(event._get("isComposing")) ||
    input.composing.get_current() == Some(true) ||
    @core.equal(event._get("keyCode"), @core.any(229)) {
    return
  }
  let target = event._get("target")
  if shortcut_text_target(target) || selected_page_text() {
    return
  }
  let key : String = event._get("key").cast()
  let code : String = event._get("code").cast()
  if code == "Space" &&
    !@core.is_nullish(closest_element(target, "button, [role=\"tab\"]")) {
    return
  }
  if !key.has_prefix("Arrow") {
    finish_key_nudge(owner)
  }
  let scene = input.scene
  let active : FixedArray[String] = input.active_ids
  let preview = input.viewing_playback
  let action = @editor.keyboard_action(
    key,
    code,
    truthy(event._get("metaKey")) || truthy(event._get("ctrlKey")),
    truthy(event._get("shiftKey")),
    preview,
    !@core.is_nullish(scene),
    !active.is_empty(),
  )
  if @editor.shortcut_consumes(action) {
    prevent_default(event)
  }
  let store = input.store
  match action {
    IgnoreShortcut => ()
    RememberPaste(in_place) => input.paste_in_place.set_current(Some(in_place))
    PreviewNotice =>
      (input.actions.notify)(
        "「この場面を編集」または Esc で編集に戻れます。",
      )
    ReturnFromPreview => (input.actions.edit_moment)(false)
    UndoShortcut => (input.actions.undo)()
    RedoShortcut => (input.actions.redo)()
    DuplicateSelection => {
      let ids = store._call("duplicate", [
        scene._get("id"),
        @core.any(input.composition_id),
        @core.any(active),
      ])
      (input.actions.set_selected_ids)(ids.cast())
    }
    SelectAllObjects => {
      let composition : String = input.composition_id
      let ids = @core.object_keys(scene._get("objects")).filter(fn(id) {
        key_visible(scene, composition, id)
      })
      (input.actions.set_selected_ids)(host_array(ids))
    }
    GroupSelection(join) =>
      store._call(if join { "link" } else { "unlink" }, [
        scene._get("id"),
        @core.any(active),
      ])
      |> ignore
    NudgeSelection(dx, dy) => key_nudge(input, owner, dx, dy)
    TogglePlayback =>
      (input.actions.play)(
        if preview || !input.has_transition {
          WholeScene
        } else {
          SelectedTransition
        },
      )
    ClearSelection => {
      (input.actions.set_selected_ids)(([] : FixedArray[String]))
      (input.actions.set_tool)(@editor.SelectTool)
      (input.actions.set_playing)(false)
      (input.actions.set_path_editing)(false)
    }
    HideSelection => {
      let composition : String = input.composition_id
      let objects = scene._get("objects")
      let ids = active
        .iter()
        .filter(fn(id) {
          !truthy(objects._get(id)._get("locked")) &&
          key_visible(scene, composition, id)
        })
        .to_array()
      if !ids.is_empty() {
        store._call("hide", [
          scene._get("id"),
          @core.any(composition),
          @core.any(ids),
        ])
        |> ignore
        let remaining = active
          .iter()
          .filter(fn(id) { !ids.contains(id) })
          .to_array()
        (input.actions.set_selected_ids)(FixedArray::from_array(remaining[:]))
        let name : String = scene
          ._get("compositions")
          ._get(composition)
          ._get("name")
          .cast()
        (input.actions.notify)(
          "\{ids.length()} 個を \{name} から非表示にしました。ほかの場面には残ります。",
        )
      }
    }
    ChooseTool(tool) => (input.actions.activate_tool)(tool)
  }
}

///|
fn use_keyboard_controls(input : EditorControls) -> Unit {
  let latest = @react.use_ref(Some(input))
  latest.set_current(Some(input))
  let owner = @react.use_ref((None : KeyNudge?))
  let store = input.store
  @react.use_effect(
    fn() {
      let window = @core.global_this()
      let clear_text = fn(event : @core.Any) {
        if !@core.is_nullish(
            closest_element(
              event._get("target"),
              "button, [role=\"button\"], .stage-surface",
            ),
          ) {
          let selection = window._call("getSelection", [])
          if !@core.is_nullish(selection) {
            selection._call("removeAllRanges", []) |> ignore
          }
        }
      }
      let composition_start = fn() {
        latest.get_current().unwrap().composing.set_current(Some(true))
        finish_key_nudge(owner)
      }
      let composition_end = fn() {
        latest.get_current().unwrap().composing.set_current(Some(false))
      }
      let blur = fn() {
        composition_end()
        finish_key_nudge(owner)
      }
      let release = fn(event : @core.Any) {
        let key : String = event._get("key").cast()
        if key.has_prefix("Arrow") {
          finish_key_nudge(owner)
        }
      }
      let pointer_down = fn(event : @core.Any) {
        finish_key_nudge(owner)
        clear_text(event)
      }
      let keydown = fn(event : @core.Any) {
        editor_key(latest.get_current().unwrap(), owner, event)
      }
      let listeners : Array[(String, @core.Any, Bool)] = [
        ("compositionstart", @core.any(composition_start), false),
        ("compositionend", @core.any(composition_end), false),
        ("blur", @core.any(blur), false),
        ("pointerdown", @core.any(pointer_down), true),
        ("focusin", @core.any(clear_text), false),
        ("keyup", @core.any(release), false),
        ("keydown", @core.any(keydown), false),
      ]
      for listener in listeners {
        let (name, handler, capture) = listener
        window._call("addEventListener", [
          @core.any(name),
          handler,
          @core.any(capture),
        ])
        |> ignore
      }
      fn() {
        for listener in listeners {
          let (name, handler, capture) = listener
          window._call("removeEventListener", [
            @core.any(name),
            handler,
            @core.any(capture),
          ])
          |> ignore
        }
        composition_end()
        finish_key_nudge(owner)
      }
    },
    [store],
  )
  let scene = input.scene
  let ids : FixedArray[String] = input.active_ids
  @react.use_effect(
    fn() {
      finish_key_nudge(owner)
      fn() { () }
    },
    [
      if @core.is_nullish(scene) {
        @core.null()
      } else {
        scene._get("id")
      },
      @core.any(input.composition_id),
      @core.any(ids.iter().to_array().join(",")),
    ],
  )
}

///|
pub fn use_editor_keyboard(input : @core.Any) -> Unit {
  use_keyboard_controls(read_native_controls(input))
}
