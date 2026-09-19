///|
extern "js" fn instance_of(value : @core.Any, type_ : @core.Any) -> Bool =
  #|(value, type) => value instanceof type

///|
extern "js" fn same_identity(a : @core.Any, b : @core.Any) -> Bool = "Object.is"

///|
extern "js" fn is_array(value : @core.Any) -> Bool = "Array.isArray"

///|
extern "js" fn owns(value : @core.Any, key : String) -> Bool = "Object.hasOwn"

///|
extern "js" fn truthy(value : @core.Any) -> Bool = "Boolean"

///|
extern "js" fn copy_record(value : @core.Any) -> @core.Any =
  #|value => ({...value})

///|
extern "js" fn stringify(value : @core.Any) -> String = "JSON.stringify"

///|
fn[T] fail(message : String) -> T {
  @core.throw_error(message)
  panic()
}

///|
fn valid_path(path : Array[String]) -> Bool {
  !path.is_empty() &&
  path
  .iter()
  .all(fn(key) {
    key != "__proto__" && key != "constructor" && key != "prototype"
  })
}

///|
fn string_array(value : @core.Any) -> Array[String] {
  if !is_array(value) {
    return fail("編集案に無効な対象が含まれています。")
  }
  let values : FixedArray[@core.Any] = value.cast()
  values
  .iter()
  .map(fn(value) {
    if @core.typeof_(value) != "string" {
      return fail("編集案に無効な対象が含まれています。")
    }
    value.cast()
  })
  .to_array()
}

///|
fn path_key(path : Array[String]) -> String {
  stringify(@core.any(FixedArray::from_array(path[:])))
}

///|
fn shared(doc : @core.Any, path : Array[String], yjs : @core.Any) -> @core.Any {
  @boundary.get_shared(doc, FixedArray::from_array(path[:]), yjs)
}

///|
fn value(doc : @core.Any, path : Array[String], yjs : @core.Any) -> @core.Any {
  @boundary.get_value(doc, FixedArray::from_array(path[:]), yjs)
}

///|
fn array_identity(array : @core.Any, yjs : @core.Any) -> String {
  stringify(
    yjs._call("relativePositionToJSON", [
      yjs._call("createRelativePositionFromTypeIndex", [array, @core.any(0)]),
    ]),
  )
}

///|
fn parent_identity(
  doc : @core.Any,
  path : Array[String],
  yjs : @core.Any,
) -> @core.Any {
  let parent = shared(doc, path[:path.length() - 1].to_owned(), yjs)
  if instance_of(parent, yjs._get("Map")) {
    @core.any(array_identity(parent, yjs))
  } else {
    @core.undefined()
  }
}

///|
fn same_value(first : @core.Any, second : @core.Any) -> Bool {
  if same_identity(first, second) {
    return true
  }
  if !truthy(first) ||
    !truthy(second) ||
    @core.typeof_(first) != "object" ||
    @core.typeof_(second) != "object" {
    return false
  }
  if is_array(first) != is_array(second) {
    return false
  }
  let keys = @core.object_keys(first)
  keys.length() == @core.object_keys(second).length() &&
  keys
  .iter()
  .all(fn(key) {
    owns(second, key) && same_value(first._get(key), second._get(key))
  })
}

///|
fn valid_duration(value : @core.Any) -> Double {
  if @core.typeof_(value) != "number" ||
    !@assets.bounded_number(value.cast(), 0.0, 120000.0) {
    return fail(
      "長さは 0〜120000 ms の有限な数値で指定してください。",
    )
  }
  value.cast()
}
