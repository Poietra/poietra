///|
extern "js" fn truthy(value : @core.Any) -> Bool = "Boolean"

///|
extern "js" fn merge(left : @core.Any, right : @core.Any) -> @core.Any =
  #|(left, right) => ({...left, ...right})

///|
extern "js" fn slice_text(value : String, limit : Int) -> String =
  #|(value, limit) => value.slice(0, limit)

///|
extern "js" fn round(value : Double) -> Double = "Math.round"

///|
extern "js" fn instance_of(value : @core.Any, type_ : @core.Any) -> Bool =
  #|(value, type) => value instanceof type

///|
fn record(entries : Array[(String, @core.Any)]) -> @core.Any {
  @core.from_entries(entries)
}

///|
fn change(path : Array[String], value : @core.Any) -> @core.Any {
  record([
    ("path", @core.any(FixedArray::from_array(path[:]))),
    ("value", value),
  ])
}

///|
fn changes_for(path : Array[String], patch : @core.Any) -> Array[@core.Any] {
  @boundary.changes_for(FixedArray::from_array(path[:]), patch)
  .iter()
  .to_array()
}

///|
fn current_scene(store : @core.Any, id : String) -> @core.Any {
  store._call("scene", [@core.any(id)])
}

///|
fn edit(
  store : @core.Any,
  changes : Array[@core.Any],
  separate? : Bool = true,
) -> Unit {
  store._call("edit", [
    @core.any(FixedArray::from_array(changes[:])),
    @core.any(separate),
  ])
  |> ignore
}

///|
fn stop_capture(store : @core.Any) -> Unit {
  store._get("undoManager")._call("stopCapturing", []) |> ignore
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

///|
fn host(store : @core.Any) -> @core.Any {
  store._get("runtime")._get("Y")
}

///|
fn shared(store : @core.Any, path : Array[String]) -> @core.Any {
  @boundary.get_shared(
    store._get("doc"),
    FixedArray::from_array(path[:]),
    host(store),
  )
}

///|
fn is_shared_map(store : @core.Any, value : @core.Any) -> Bool {
  instance_of(value, host(store)._get("Map"))
}

///|
fn number(value : @core.Any) -> Double {
  value.cast()
}

///|
fn channels() -> Array[@scene.PropertyChannel] {
  [
    @scene.Position,
    Opacity,
    Size,
    Rotation,
    Fill,
    Stroke,
    StrokeWidth,
    FontSize,
    CornerRadius,
    ShapePath,
    Reveal,
  ]
}

///|
fn channel_key(channel : @scene.PropertyChannel) -> String {
  @editor.property_channel_name(channel) + "Timing"
}
