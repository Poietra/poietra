///|
fn record(value : @core.Any) -> @core.Any {
  if !@core.is_nullish(value) &&
    @core.typeof_(value) == "object" &&
    !@core.is_array(value) {
    value
  } else {
    @core.new_object()
  }
}

///|
fn string(value : @core.Any) -> String? {
  if @core.typeof_(value) == "string" {
    Some(value.cast())
  } else {
    None
  }
}

///|
fn read_state(value : @core.Any) -> @presence.State {
  let data = record(value)
  let user = record(data._get("user"))
  let editor = record(data._get("editor"))
  let cursor = record(editor._get("cursor"))
  let selected = editor._get("selectedIds")
  let selected_ids = []
  if @core.is_array(selected) {
    for id in (selected.cast() : FixedArray[@core.Any]) {
      if string(id) is Some(value) {
        selected_ids.push(value)
      }
      if selected_ids.length() == 12 {
        break
      }
    }
  }
  let cursor = if @core.typeof_(cursor._get("x")) == "number" &&
    @core.typeof_(cursor._get("y")) == "number" {
    Some(@presence.Cursor::{
      x: cursor._get("x").cast(),
      y: cursor._get("y").cast(),
    })
  } else {
    None
  }
  @presence.clean_state(
    string(user._get("name")),
    string(user._get("color")),
    string(editor._get("sceneId")),
    string(editor._get("compositionId")),
    selected_ids,
    cursor,
  )
}

///|
fn optional_string(value : String?) -> @core.Any {
  match value {
    Some(value) => @core.any(value)
    None => @core.undefined()
  }
}

///|
fn write_state(state : @presence.State) -> @core.Any {
  @core.from_entries([
    (
      "user",
      @core.from_entries([
        ("name", @core.any(state.name)),
        ("color", @core.any(state.color)),
      ]),
    ),
    (
      "editor",
      @core.from_entries([
        ("sceneId", optional_string(state.scene_id)),
        ("compositionId", optional_string(state.composition_id)),
        (
          "selectedIds",
          @core.any(
            FixedArray::makei(state.selected_ids.length(), fn(index) {
              state.selected_ids[index]
            }),
          ),
        ),
        (
          "cursor",
          match state.cursor {
            None => @core.null()
            Some(point) =>
              @core.from_entries([
                ("x", @core.any(point.x)),
                ("y", @core.any(point.y)),
              ])
          },
        ),
      ]),
    ),
  ])
}

///|
pub fn read_presence_update(
  update : @core.Any,
  previous : @core.Any,
) -> @core.Any {
  let bytes : Int = update._get("byteLength").cast()
  if bytes > 16384 {
    @core.throw_error("Presence is too large")
  }
  let decoder = @wire.decoder(update)
  let count = @wire.read_uint(decoder)
  if count > 100.0 {
    @core.throw_error("Too many presence entries")
  }
  let mut next = previous
  let mut old = if @core.is_nullish(previous) {
    None
  } else {
    Some(@presence.ClockState::{
      client_id: previous._get("clientId").cast(),
      clock: previous._get("clock").cast(),
      live: !@core.is_null(previous._get("state")),
    })
  }
  for index = 0; index < count.to_int(); index = index + 1 {
    let client_id = @wire.read_uint(decoder)
    let clock = @wire.read_uint(decoder)
    let value = @core.global_this()
      ._get("JSON")
      ._call("parse", [@core.any(@wire.read_string(decoder))])
    let live = !@core.is_null(value)
    if !@presence.accepts(old, client_id, clock, live) {
      continue
    }
    old = Some({ client_id, clock, live, })
    next = @core.from_entries([
      ("clientId", @core.any(client_id)),
      ("clock", @core.any(clock)),
      (
        "state",
        if live {
          write_state(read_state(value))
        } else {
          @core.null()
        },
      ),
    ])
  }
  next
}

///|
pub fn presence_message(entries : FixedArray[@core.Any]) -> @core.Any {
  let update = @wire.encoder()
  @wire.write_uint(update, entries.length().to_double())
  for entry in entries {
    @wire.write_uint(update, entry._get("clientId").cast())
    @wire.write_uint(update, entry._get("clock").cast())
    @wire.write_string(
      update,
      @core.global_this()
      ._get("JSON")
      ._call("stringify", [entry._get("state")])
      .cast(),
    )
  }
  let message = @wire.encoder()
  @wire.write_uint(message, 1.0)
  @wire.write_bytes(message, @wire.to_bytes(update))
  @wire.to_bytes(message)
}

///|
/// Bound each packet so older y-websocket clients can relay it without exceeding
/// the per-message input limit. A full 500-person roster is several packets.
pub fn presence_messages(entries : FixedArray[@core.Any]) -> Array[@core.Any] {
  let packets = []
  let chunk = []
  let mut size = 0
  for entry in entries {
    let length : Int = presence_message([entry])._get("byteLength").cast()
    if !chunk.is_empty() && (chunk.length() >= 50 || size + length > 16000) {
      packets.push(presence_message(FixedArray::from_array(chunk[:])))
      chunk.clear()
      size = 0
    }
    chunk.push(entry)
    size += length
  }
  if !chunk.is_empty() {
    packets.push(presence_message(FixedArray::from_array(chunk[:])))
  }
  packets
}
