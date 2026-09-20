///|
#module("#poietra/ui-host")
extern "js" fn editor_context_runtime() -> @core.Any = "editorContextRuntime"

///|
fn use_editor_state() -> @core.Any {
  let value : @core.Any = @react.use_context(editor_context_runtime().cast())
  if !truthy(value) {
    ui_throw(
      @core.new(@core.global_this()._get("Error"), [
        @core.any("Editor context is missing"),
      ]),
    )
  }
  value
}

///|
/// Snapshots retain unchanged branches; subscribing to a field preserves that
/// identity across presence, connection and history notifications.
fn use_store_field(
  store : @core.Any,
  field : String,
  enabled? : Bool = true,
  fallback? : @core.Any = @core.undefined(),
) -> @core.Any {
  let (subscribe, snapshot) = @react.use_memo(
    fn() {
      (
        fn(listener : () -> Unit) -> () -> Unit {
          if enabled && truthy(store) && truthy(store._get("subscribe")) {
            store._get("subscribe")._invoke([@core.any(listener)]).cast()
          } else {
            fn() { () }
          }
        },
        fn() {
          if enabled && truthy(store) && truthy(store._get("snapshot")) {
            let value = store._get("snapshot")._invoke([])._get(field)
            if @core.is_undefined(value) {
              fallback
            } else {
              value
            }
          } else {
            fallback
          }
        },
      )
    },
    [store, @core.any(field), @core.any(enabled), fallback],
  )
  @react.use_sync_external_store(subscribe, snapshot)
}

///|
fn use_editor_position(editor : @core.Any) -> Double {
  match @react.use_context(studio_position_context) {
    Some(view) if @core.equal(
        @core.any(view.source),
        editor._get("positionSource"),
      ) => view.time
    _ => editor._get("playhead").cast()
  }
}

///|
fn use_editor_peers(editor : @core.Any) -> @core.Any {
  use_store_field(
    if truthy(editor._get("positionSource")) {
      editor._get("store")
    } else {
      @core.undefined()
    },
    "peers",
    fallback=editor._get("peers"),
  )
}

///|
/// A stable projection of a native immutable snapshot. The cache belongs to
/// this subscription, so different panels cannot overwrite one another's view.
fn use_store_fields(
  store : @core.Any,
  fields : FixedArray[String],
) -> @core.Any {
  let snapshot = @react.use_memo(
    fn() {
      let previous = Ref(@core.undefined())
      fn() {
        let source = store._get("snapshot")._invoke([])
        if truthy(previous.val) &&
          fields
          .iter()
          .all(fn(field) {
            @core.equal(previous.val._get(field), source._get(field))
          }) {
          return previous.val
        }
        let value = @core.from_entries(
          fields
          .iter()
          .map(fn(field) { (field, source._get(field)) })
          .to_array(),
        )
        previous.val = value
        value
      }
    },
    [store, @core.any(fields.join(","))],
  )
  @react.use_sync_external_store(store._get("subscribe").cast(), snapshot)
}

///|
/// Compatibility API: consumers asking for the whole editor still receive the
/// live clock and presence. Internal components subscribe only to what they use.
pub fn use_editor() -> @core.Any {
  let editor = use_editor_state()
  let time = use_editor_position(editor)
  let peers = use_editor_peers(editor)
  @react.use_memo(
    fn() {
      let value = ui_shallow_copy(editor)
      value._set("playhead", @core.any(time))
      value._set("peers", peers)
      value
    },
    [editor, @core.any(time), peers],
  )
}
