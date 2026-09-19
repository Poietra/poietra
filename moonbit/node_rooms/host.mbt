///|
#module("node:fs")
extern "js" fn write_file(
  path : String,
  bytes : @core.Any,
  options : @core.Any,
) -> Unit = "writeFileSync"

///|
// The upstream variadic path/process wrappers currently call CommonJS require.
// Bind the fixed-arity ESM export directly for the native Node server.
#module("node:path")
extern "js" fn resolve_path(left : String, right : String) -> String = "resolve"

///|
extern "js" fn define_property(
  target : @core.Any,
  name : String,
  get : () -> @core.Any,
  set : (@core.Any) -> Unit,
) -> Unit =
  #|(target, name, get, set) => { Object.defineProperty(target, name, { get, set, enumerable: true }); }

///|
extern "js" fn constructor_adapter(create : (String) -> @core.Any) -> @core.Any =
  #|create => function Room(id) { return create(id); }

///|
extern "js" fn bytes(value : @core.Any) -> @core.Any =
  #|value => new Uint8Array(value)

///|
fn native_error(error : Error) -> @core.Any {
  match error {
    @core.ThrowError(value) => value
    _ => @core.any(error)
  }
}

///|
fn rethrow(error : Error) -> @core.Any {
  @core.throw_(native_error(error))
  @core.undefined()
}

///|
fn array(values : Array[@core.Any]) -> @core.Any {
  @core.any(FixedArray::makei(values.length(), fn(index) { values[index] }))
}

///|
fn set_values(values : @collection.JsSet[Double]) -> @core.Any {
  let result = []
  values.forEach(fn(value) { result.push(@core.any(value)) })
  array(result)
}
