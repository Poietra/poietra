///|
pub fn edit_batch(
  store : @core.Any,
  changes : FixedArray[@core.Any],
  separate : Bool,
) -> Unit {
  let result = try {
    if separate {
      stop_capture(store)
    }
    defer (if separate { stop_capture(store) })
    @core.throwable(fn() {
      @boundary.apply_changes(
        store._get("doc"),
        changes,
        @core.any("poietra-local"),
        host(store),
      )
    })
    Ok(())
  } catch {
    error => Err(error)
  }
  if result is Err(error) {
    @core.throw_(native_error(error))
  }
}

///|
pub fn begin_gesture(store : @core.Any) -> Unit {
  stop_capture(store)
  store
  ._get("undoManager")
  ._set("captureTimeout", @core.global_this()._get("Infinity"))
}

///|
pub fn end_gesture(store : @core.Any) -> Unit {
  store._get("undoManager")._set("captureTimeout", @core.any(400))
  stop_capture(store)
  flush_documents(store)
}

///|
pub fn undo_edit(store : @core.Any) -> Int {
  let retained = @undo.undo(store._get("undoManager")._get("moon").cast())
  flush_documents(store)
  if !@core.is_nullish(store._get("moon")) {
    session(store).publish()
  }
  retained
}

///|
pub fn redo_edit(store : @core.Any) -> Int {
  let retained = @undo.redo(store._get("undoManager")._get("moon").cast())
  flush_documents(store)
  if !@core.is_nullish(store._get("moon")) {
    session(store).publish()
  }
  retained
}

///|
pub fn rollback_gesture(store : @core.Any, expected : @core.Any) -> Bool {
  let result = try {
    defer (if !@core.is_nullish(store._get("moon")) {
      session(store).publish()
    })
    Ok(
      @core.throwable(fn() {
        @undo.rollback_gesture(
          store._get("undoManager")._get("moon").cast(),
          expected,
        )
      }),
    )
  } catch {
    error => Err(error)
  }
  match result {
    Ok(value) => value
    Err(error) => {
      @core.throw_(native_error(error))
      false
    }
  }
}
