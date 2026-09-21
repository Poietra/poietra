///|
extern "js" fn is_array(value : @core.Any) -> Bool = "Array.isArray"

///|
extern "js" fn strict_equal(a : @core.Any, b : @core.Any) -> Bool =
  #|(a, b) => a === b

///|
extern "js" fn merge_values(a : @core.Any, b : @core.Any) -> @core.Any =
  #|(a, b) => ({...a, ...b})

///|
extern "js" fn put_own(
  value : @core.Any,
  key : String,
  item : @core.Any,
) -> Unit =
  #|(value, key, item) => { Object.defineProperty(value, key, {value: item, writable: true, enumerable: true, configurable: true}); }

///|
extern "js" fn make_timing(
  start : @core.Any,
  duration : @core.Any,
  easing : @core.Any,
) -> @core.Any =
  #|(start, duration, easing) => ({start, duration, easing})

///|
fn is_record(value : @core.Any) -> Bool {
  !@core.is_nullish(value) &&
  @core.typeof_(value) == "object" &&
  !is_array(value)
}

///|
pub fn is_valid_easing(value : @core.Any) -> Bool {
  if @core.typeof_(value) == "string" {
    let name : String = value.cast()
    return name == "linear" ||
      name == "easeInOut" ||
      name == "easeIn" ||
      name == "easeOut"
  }
  if @core.is_nullish(value) ||
    @core.typeof_(value) != "object" ||
    is_array(value) {
    return false
  }
  let keys = @core.object_keys(value)
  if keys.length() != 5 {
    return false
  }
  for key in keys {
    if key != "type" && key != "x1" && key != "y1" && key != "x2" && key != "y2" {
      return false
    }
  }
  if !strict_equal(value._get("type"), @core.any("cubicBezier")) {
    return false
  }
  for key in ["x1", "y1", "x2", "y2"] {
    if @core.typeof_(value._get(key)) != "number" {
      return false
    }
  }
  @scene.valid_easing(decode_Easing(value))
}
