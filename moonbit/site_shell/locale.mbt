///|
fn optional_string(value : @core.Any) -> String? {
  if @core.is_nullish(value) {
    None
  } else {
    Some(value.cast())
  }
}

///|
pub fn resolve_locale(input : @core.Any) -> String {
  @locale.resolve_locale(input)
}

///|
fn stored_value(key : String) -> @core.Any {
  @core.throwable(fn() {
    @core.global_this()._get("localStorage")._call("getItem", [@core.any(key)])
  }) catch {
    _ => @core.null()
  }
}

///|
pub fn get_locale() -> String {
  let global = @core.global_this()
  let location = global._get("location")
  let query = if @core.is_undefined(location) {
    @core.null()
  } else {
    let url = @core.new(global._get("URL"), [location._get("href")])
    let selected = url._get("searchParams")._call("get", [@core.any("lang")])
    if optional_string(selected)
      .map(fn(value) { @site.locale(value) is Some(_) })
      .unwrap_or(false) {
      selected
    } else if @site.japanese_path(url._get("pathname").cast()) {
      @core.any("ja")
    } else {
      @core.null()
    }
  }
  let navigator = global._get("navigator")
  let languages = if @core.is_undefined(navigator) {
    @core.any(([] : FixedArray[@core.Any]))
  } else {
    let values = navigator._get("languages")
    if !@core.is_nullish(values) && (values._get("length").cast() : Int) > 0 {
      values
    } else {
      @core.any(([navigator._get("language")] : FixedArray[@core.Any]))
    }
  }
  resolve_locale(
    @core.from_entries([
      ("query", query),
      ("stored", stored_value("poietra-locale")),
      ("languages", languages),
    ]),
  )
}

///|
pub fn apply_page_language(locale : String) -> Unit {
  let document = @core.global_this()._get("document")
  document._get("documentElement")._set("lang", @core.any(locale))
  let copy = @site.page_copy(@site.locale(locale).unwrap_or(English))
  for
    selector in [
      "meta[name=\"description\"]", "meta[property=\"og:description\"]",
    ] {
    let element = document._call("querySelector", [@core.any(selector)])
    if !@core.is_nullish(element) {
      element._call("setAttribute", [
        @core.any("content"),
        @core.any(copy.description),
      ])
      |> ignore
    }
  }
}

///|
pub fn page_copy(locale : String) -> @core.Any {
  let copy = @site.page_copy(@site.locale(locale).unwrap_or(English))
  @core.from_entries([
    ("description", @core.any(copy.description)),
    ("loadError", @core.any(copy.loadError)),
    ("retryHint", @core.any(copy.retryHint)),
    ("retry", @core.any(copy.retry)),
    ("projectError", @core.any(copy.projectError)),
  ])
}

///|
pub fn is_editor_location(url : @core.Any) -> Bool {
  let params = url._get("searchParams")
  @site.editor_path(
    url._get("pathname").cast(),
    params._call("has", [@core.any("room")]).cast(),
    params._call("has", [@core.any("projects")]).cast(),
    params._call("has", [@core.any("auth_error")]).cast(),
  )
}

///|
pub fn last_room() -> @core.Any {
  let value = stored_value("poietra-last-room")
  if !@core.is_nullish(value) && @editor.valid_room_id(value.cast()) {
    value
  } else {
    @core.null()
  }
}

///|
pub fn room_link(room : String) -> String {
  let params = @core.new(@core.global_this()._get("URLSearchParams"), [
    @core.from_entries([("room", @core.any(room))]),
  ])
  "/?" + (params._call("toString", []).cast() : String)
}
