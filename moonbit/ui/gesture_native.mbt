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
