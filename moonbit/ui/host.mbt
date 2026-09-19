///|
/// Foreign children and props are opaque React values, not document state.
priv struct HostNode {
  value : @core.Any
}

///|
impl @react.ReactNode for HostNode with fn to_react_node(self) {
  self.value
}

///|
fn children(input : @core.Any) -> HostNode {
  { value: input._get("children"), }
}

///|
#module("#poietra/ui-host")
extern "js" fn icon_component(name : String) -> @core.Any = "iconComponent"

///|
#module("#poietra/ui-host")
extern "js" fn ui_component(library : String, name : String) -> @core.Any = "uiComponent"

///|
#module("#poietra/ui-host")
extern "js" fn class_names(values : FixedArray[@core.Any]) -> String = "classNames"

///|
fn classes(values : Array[@core.Any]) -> @core.Any {
  @core.any(
    class_names(FixedArray::makei(values.length(), fn(i) { values[i] })),
  )
}

///|
fn h(
  tag : String,
  props : Map[String, @core.Any],
  nodes : Array[&@react.ReactNode],
) -> @react.Element {
  @react.h(tag, nodes, props~)
}

///|
fn ui(
  library : String,
  name : String,
  props : Map[String, @core.Any],
  nodes : Array[&@react.ReactNode],
) -> @react.Element {
  @react.jsx(ui_component(library, name), nodes, props~)
}

///|
fn icon(
  name : String,
  size : Int,
  props? : Map[String, @core.Any] = Map([]),
) -> @react.Element {
  props["size"] = @core.any(size)
  @react.jsx(icon_component(name), [], props~)
}

///|
fn props_except(
  input : @core.Any,
  except : Array[String],
) -> Map[String, @core.Any] {
  let result = Map([])
  for key in @core.object_keys(input) {
    if !except.contains(key) {
      result[key] = input._get(key)
    }
  }
  result
}

///|
extern "js" fn truthy(value : @core.Any) -> Bool = "Boolean"

///|
extern "js" fn number_value(text : String) -> Double = "Number"

///|
extern "js" fn string_value(value : @core.Any) -> String = "String"

///|
extern "js" fn round_number(value : Double) -> Double = "Math.round"

///|
fn optional_number(
  input : @core.Any,
  key : String,
  fallback : Double,
) -> Double {
  let value = input._get(key)
  if @core.is_undefined(value) {
    fallback
  } else {
    value.cast()
  }
}

///|
extern "js" fn blur(event : @core.Any) -> Unit =
  #|event => event.currentTarget.blur()
