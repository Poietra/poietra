///|
priv struct RoomChat {
  doc : @core.Any
  entries : @core.Any
  runtime : @core.Any
  cache : @core.Any
  listeners : @collection.JsSet[() -> Unit]
  mut messages : FixedArray[@core.Any]
}

///|
extern "js" fn instance_of(value : @core.Any, class_ : @core.Any) -> Bool =
  #|(value, type) => value instanceof type

///|
fn RoomChat::refresh(self : RoomChat, events : FixedArray[@core.Any]) -> Unit {
  for event in events {
    // Each message is a Y.Map; nested plain scope/proposal values are atomic.
    let mut target = event._get("target")
    while !@core.is_nullish(target) && !@core.equal(target, self.entries) {
      self.cache._call("delete", [target]) |> ignore
      target = target._get("parent")
    }
  }
  let values : FixedArray[@core.Any] = self.entries._call("toArray", []).cast()
  let messages = []
  for index = (values.length() - 300).max(0)
      index < values.length()
      index = index + 1 {
    let entry = values[index]
    if !instance_of(entry, self.runtime._get("Map")) {
      continue
    }
    let cached = self.cache._call("get", [entry])
    let message = if !@core.is_undefined(cached) {
      cached
    } else {
      let value = entry._call("toJSON", [])
      let parsed = if @boundary.valid_chat_message(value) {
        @boundary.write_chat_message(@boundary.read_chat_message(value))
      } else {
        @core.null()
      }
      self.cache._call("set", [entry, parsed]) |> ignore
      parsed
    }
    if !@core.is_null(message) {
      messages.push(message)
    }
  }
  self.messages = FixedArray::makei(messages.length(), fn(i) { messages[i] })
  self.listeners.forEach(fn(callback) { callback() })
}

///|
fn RoomChat::append(self : RoomChat, message : @core.Any) -> Unit {
  if !@boundary.valid_chat_message(message) {
    @core.throw_error("Invalid chat message")
    return
  }
  let parsed = @boundary.write_chat_message(
    @boundary.read_chat_message(message),
  )
  for existing in self.messages {
    if @core.equal(existing._get("id"), parsed._get("id")) {
      return
    }
  }
  self.doc._call("transact", [
    @core.any(fn() {
      let entry = @core.new(self.runtime._get("Map"), [])
      for key in @core.object_keys(parsed) {
        entry._call("set", [@core.any(key), parsed._get(key)]) |> ignore
      }
      self.entries._call("push", [@core.any(([entry] : FixedArray[@core.Any]))])
      |> ignore
      let length : Int = self.entries._get("length").cast()
      if length > 300 {
        self.entries._call("delete", [@core.any(0), @core.any(length - 300)])
        |> ignore
      }
    }),
    @core.any("poietra-chat"),
  ])
  |> ignore
}

///|
fn RoomChat::patch(self : RoomChat, id : String, patch : @core.Any) -> Unit {
  let values : FixedArray[@core.Any] = self.entries._call("toArray", []).cast()
  for entry in values {
    if !instance_of(entry, self.runtime._get("Map")) ||
      !@core.equal(entry._call("get", [@core.any("id")]), @core.any(id)) {
      continue
    }
    self.doc._call("transact", [
      @core.any(fn() {
        for key in @core.object_keys(patch) {
          entry._call("set", [@core.any(key), patch._get(key)]) |> ignore
        }
      }),
      @core.any("poietra-chat"),
    ])
    |> ignore
    return
  }
}

///|
pub fn create_room_chat(doc : @core.Any, runtime : @core.Any) -> @core.Any {
  let state : RoomChat = {
    doc,
    entries: doc._call("getArray", [@core.any("chat")]),
    runtime,
    cache: @core.new(@core.global_this()._get("WeakMap"), []),
    listeners: @collection.JsSet::new(),
    messages: [],
  }
  let refresh = fn(events : FixedArray[@core.Any]) { state.refresh(events) }
  state.entries._call("observeDeep", [@core.any(refresh)]) |> ignore
  state.refresh([])
  doc._call("on", [
    @core.any("destroy"),
    @core.any(fn() {
      state.entries._call("unobserveDeep", [@core.any(refresh)]) |> ignore
      state.listeners.clear()
    }),
  ])
  |> ignore
  @core.from_entries([
    ("doc", doc),
    ("snapshot", @core.any(fn() { state.messages })),
    (
      "subscribe",
      @core.any(fn(callback : () -> Unit) {
        state.listeners.add(callback) |> ignore
        fn() { state.listeners.delete(callback) |> ignore }
      }),
    ),
    ("append", @core.any(fn(message : @core.Any) { state.append(message) })),
    (
      "patch",
      @core.any(fn(id : String, patch : @core.Any) { state.patch(id, patch) }),
    ),
  ])
}
