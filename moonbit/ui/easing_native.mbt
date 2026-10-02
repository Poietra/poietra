///|
/// Public JS props are decoded here; internal callers retain Easing and typed
/// callbacks all the way through rendering and pointer gestures.
pub fn easing_editor(input : @core.Any) -> @react.Element {
  render_easing_editor({
    value: read_optional_easing(input._get("value")),
    label: input._get("label").cast(),
    disabled: truthy(input._get("disabled")),
    disabled_reason: if truthy(input._get("disabledReason")) {
      Some(input._get("disabledReason").cast())
    } else {
      None
    },
    current: if truthy(input._get("getValue")) {
      Some(fn() { read_optional_easing(input._get("getValue")._invoke([])) })
    } else {
      None
    },
    on_change: fn(value, separate) {
      let args : FixedArray[@core.Any] = if separate {
        [@boundary.write_easing(value)]
      } else {
        [@boundary.write_easing(value), @core.any(false)]
      }
      input._get("onChange")._invoke(args) |> ignore
    },
  })
}

///|
fn read_optional_easing(value : @core.Any) -> @scene.Easing? {
  if @core.is_nullish(value) {
    None
  } else {
    Some(@boundary.read_easing(value))
  }
}

///|
/// Native identities have no domain fields. In particular, an Undo entry may
/// only be compared or passed back to the store that created it.
#external
priv type UndoEntry

///|
extern "js" fn same_undo_entry(a : UndoEntry, b : UndoEntry) -> Bool =
  #|(a, b) => a === b

///|
impl Eq for UndoEntry with fn equal(a, b) {
  same_undo_entry(a, b)
}

///|
#external
priv type GestureHistory

///|
fn native_gesture_history(store : @core.Any) -> GestureHistory {
  store.cast()
}

///|
fn GestureHistory::top(self : GestureHistory) -> UndoEntry? {
  let value = top_undo(@core.any(self))
  if @core.is_undefined(value) {
    None
  } else {
    Some(value.cast())
  }
}

///|
extern "js" fn GestureHistory::begin(self : GestureHistory) -> Unit =
  #|store => { store.beginGesture(); }

///|
fn GestureHistory::end(self : GestureHistory) -> Unit {
  ui_quiet(@core.any(self), "endGesture")
}

///|
extern "js" fn GestureHistory::rollback(
  self : GestureHistory,
  entry : UndoEntry,
) -> Unit =
  #|(store, entry) => { store.rollbackGesture(entry); }

///|
fn top_undo(store : @core.Any) -> @core.Any {
  let stack : FixedArray[@core.Any] = store
    ._get("undoManager")
    ._get("undoStack")
    .cast()
  if stack.is_empty() {
    @core.undefined()
  } else {
    stack[stack.length() - 1]
  }
}

///|
fn native_group_easing(
  store : @core.Any,
  scene_id : String,
  transition_id : String,
  ids : FixedArray[String],
) -> @scene.Easing? {
  let current = store._call("project", [])._get("scenes")._get(scene_id)
  if !truthy(current) {
    return None
  }
  read_optional_easing(
    @boundary.common_track_value(
      @boundary.group_animation_targets(current, transition_id, ids)
      ._get("targets")
      .cast(),
      "easing",
    ),
  )
}
