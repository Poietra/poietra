///|
#module("#poietra/site-shell-host")
extern "js" fn create_boundary(
  initial : @core.Any,
  recover : (@core.Any) -> @core.Any,
  render : (@core.Any, @core.Any) -> @core.Any,
) -> @core.Any = "createBoundary"

///|
pub fn h(
  tag : String,
  props : Map[String, @core.Any],
  children : Array[&@react.ReactNode],
) -> @react.Element {
  @react.jsx_tag(tag, children, props~)
}

///|
pub fn failure_view(locale : @site.Locale) -> @react.Element {
  let copy = @site.page_copy(locale)
  h("div", { "className": @core.any("entry-message") }, [
    h(
      "img",
      { "src": @core.any("/poietra.svg"), "alt": @core.any("Poietra") },
      [],
    ),
    h("h1", {}, [copy.loadError]),
    h("p", {}, [copy.retryHint]),
    h(
      "button",
      {
        "onClick": @core.any(fn() {
          @core.global_this()._get("location")._call("reload", []) |> ignore
        }),
      },
      [copy.retry],
    ),
  ])
}

///|
let boundary_class : @core.Any = create_boundary(
  @core.from_entries([("error", @core.any(false))]),
  fn(_) { @core.from_entries([("error", @core.any(true))]) },
  fn(props, state) {
    if !(state._get("error").cast() : Bool) {
      return props._get("children")
    }
    let document = @core.global_this()._get("document")
    let locale = if !@core.is_undefined(document) &&
      (document._get("documentElement")._get("lang").cast() : String) == "ja" {
      @site.Japanese
    } else {
      @site.English
    }
    failure_view(locale).as_any()
  },
)

///|
pub fn boundary_component() -> @core.Any {
  boundary_class
}

///|
pub fn protect(element : @react.Element) -> @react.Element {
  @react.strict_mode([@react.jsx(boundary_class, [element])])
}
