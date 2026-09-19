///|
/// Yjs identities, Items and clock sets stay native. No document conversion or
/// JSON copying is involved in inspecting a history entry.
extern "js" fn instance_of(value : @core.Any, type_ : @core.Any) -> Bool =
  #|(value, type) => value instanceof type

///|
extern "js" fn values(map : @core.Any) -> FixedArray[@core.Any] =
  #|map => Array.from(map.values())

///|
extern "js" fn keys(map : @core.Any) -> FixedArray[String] =
  #|map => Array.from(map.keys())

///|
extern "js" fn event_path(event : @core.Any) -> FixedArray[String] =
  #|event => event.path.map(String)

///|
extern "js" fn string_value(value : @core.Any) -> String = "String"

///|
extern "js" fn truthy(value : @core.Any) -> Bool = "Boolean"

///|
extern "js" fn restore_stack(stack : @core.Any, earlier : @core.Any) -> Unit =
  #|(stack, earlier) => { stack.unshift(...earlier); }

///|
fn get(map : @core.Any, key : String) -> @core.Any {
  map._call("get", [@core.any(key)])
}

///|
fn top(stack : @core.Any) -> @core.Any {
  stack._call("at", [@core.any(-1)])
}

///|
fn hide_earlier(stack : @core.Any) -> @core.Any {
  let length : Int = stack._get("length").cast()
  stack._call("splice", [@core.any(0), @core.any((length - 1).max(0))])
}

///|
fn Session::is_map(self : Session, value : @core.Any) -> Bool {
  instance_of(value, self.yjs._get("Map"))
}

///|
fn Session::is_array(self : Session, value : @core.Any) -> Bool {
  instance_of(value, self.yjs._get("Array"))
}

///|
fn Session::deleted(self : Session, set : @core.Any, item : @core.Any) -> Bool {
  self.yjs._call("isDeleted", [set, item._get("id")]).cast()
}

///|
fn Session::shared(self : Session, path : FixedArray[String]) -> @core.Any {
  @boundary.get_shared(self.manager._get("doc"), path, self.yjs)
}

///|
fn timing_keys() -> Array[String] {
  [
    "positionTiming", "opacityTiming", "sizeTiming", "rotationTiming", "fillTiming",
    "strokeTiming", "strokeWidthTiming", "fontSizeTiming", "cornerRadiusTiming",
    "pathTiming", "revealTiming",
  ]
}

///|
fn native_error(error : Error) -> @core.Any {
  match error {
    @core.ThrowError(value) => value
    _ =>
      @core.new(@core.global_this()._get("Error"), [
        @core.any(error.to_string()),
      ])
  }
}
