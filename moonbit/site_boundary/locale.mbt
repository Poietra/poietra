///|
extern "js" fn locale_language(tag : String) -> String =
  #|tag => new Intl.Locale(tag).language

///|
pub fn normalized_language(tag : String) -> String? {
  Some(@core.throwable(fn() { locale_language(tag) })) catch {
    _ => None
  }
}

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
  let input = if @core.is_nullish(input) { @core.new_object() } else { input }
  let preferences = input._get("languages")
  let languages = []
  if !@core.is_nullish(preferences) {
    for tag in (preferences.cast() : FixedArray[String]) {
      languages.push(@core.throwable(fn() { locale_language(tag) })) catch {
        _ => ()
      }
    }
  }
  @site.locale_name(
    @site.resolve_locale(
      optional_string(input._get("query")),
      optional_string(input._get("stored")),
      languages,
    ),
  )
}
