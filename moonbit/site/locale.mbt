///|
pub(all) enum Locale {
  English
  Japanese
} derive(Eq)

///|
pub fn locale(value : String) -> Locale? {
  match value {
    "en" => Some(English)
    "ja" => Some(Japanese)
    _ => None
  }
}

///|
pub fn locale_name(value : Locale) -> String {
  match value {
    English => "en"
    Japanese => "ja"
  }
}

///|
pub fn resolve_locale(
  query : String?,
  stored : String?,
  languages : Array[String],
) -> Locale {
  for selected in [query, stored] {
    if selected is Some(value) && locale(value) is Some(locale) {
      return locale
    }
  }
  for language in languages {
    if locale(language) is Some(locale) {
      return locale
    }
  }
  English
}

///|
pub fn editor_path(
  path : String,
  has_room : Bool,
  has_projects : Bool,
  has_auth_error : Bool,
) -> Bool {
  ["/studio", "/studio/", "/studio/index.html"].contains(path) ||
  has_room ||
  has_projects ||
  has_auth_error
}

///|
pub fn japanese_path(path : String) -> Bool {
  ["/ja", "/ja/", "/ja/index.html"].contains(path)
}

///|
pub(all) enum Template {
  Blank
  Example
} derive(Eq)

///|
pub fn template_name(value : Template) -> String {
  match value {
    Blank => "blank"
    Example => "example"
  }
}

///|
pub fn study_position(time : Double) -> (Double, Double, Double) {
  let t = time / 2000.0
  let rest = 1.0 - t
  (
    rest * rest * rest * 72.0 +
    3.0 * rest * rest * t * 240.0 +
    3.0 * rest * t * t * 300.0 +
    t * t * t * 488.0,
    rest * rest * rest * 204.0 +
    3.0 * rest * rest * t * 204.0 +
    3.0 * rest * t * t * 76.0 +
    t * t * t * 76.0,
    (time / 300.0).min(1.0),
  )
}
