///|
pub(all) struct WeightedValue {
  value : String
  quality : Int
}

///|
fn quality(value : String) -> Int {
  let parts = value.split(".").to_array()
  if parts.length() > 2 || !(parts[0] == "0" || parts[0] == "1") {
    return 0
  }
  let fraction = if parts.length() == 2 { parts[1] } else { ""[:] }
  if fraction.length() > 3 {
    return 0
  }
  let mut digits = 0
  for index = 0; index < fraction.length(); index = index + 1 {
    let digit = fraction.code_unit_at(index).to_int() - 48
    if digit < 0 || digit > 9 || (parts[0] == "1" && digit != 0) {
      return 0
    }
    digits = digits * 10 + digit
  }
  if parts[0] == "1" {
    return 1000
  }
  for index = fraction.length(); index < 3; index = index + 1 {
    digits *= 10
  }
  digits
}

///|
pub fn weighted_values(header : String?) -> Array[WeightedValue] {
  let values = []
  for part in header.unwrap_or("").split(",") {
    let parts = @editor.trim_text(part.to_owned()).split(";").to_array()
    let value = parts[0].to_owned().to_lower()
    if value.is_empty() {
      continue
    }
    let mut weight = 1000
    for index = 1; index < parts.length(); index = index + 1 {
      let parameter = @editor.trim_text(parts[index].to_owned())
      let pieces = parameter.split("=").to_array()
      if pieces.length() >= 2 &&
        @editor.trim_text(pieces[0].to_owned()).to_owned().to_lower() == "q" {
        weight = if pieces.length() == 2 {
          quality(@editor.trim_text(pieces[1].to_owned()).to_owned())
        } else {
          0
        }
        break
      }
    }
    values.push({ value, quality: weight, })
  }
  values
}

///|
pub fn prefers_markdown(header : String?) -> Bool {
  let values = weighted_values(header)
  let markdown = values
    .iter()
    .find_first(fn(entry) { entry.value == "text/markdown" })
    .map(fn(entry) { entry.quality })
    .unwrap_or(0)
  let mut html = 0
  for mime in ["text/html", "text/*", "*/*"] {
    if values.iter().find_first(fn(entry) { entry.value == mime })
      is Some(entry) {
      html = entry.quality
      break
    }
  }
  markdown > 0 && markdown >= html
}

///|
pub(all) enum PageKind {
  Home
  Editor
} derive(Eq)

///|
pub(all) struct PagePlan {
  kind : PageKind
  locale : @site.Locale
  asset_path : String
  content_type : String
  headers : Array[(String, String)]
}

///|
pub fn page_plan(
  path : String,
  editor : Bool,
  query : String?,
  accept : String?,
  accept_language : String?,
  normalize_language : (String) -> String?,
) -> PagePlan? {
  if ![
      "/", "/index.html", "/ja", "/ja/", "/ja/index.html", "/studio", "/studio/",
      "/studio/index.html",
    ].contains(path) {
    return None
  }
  if editor {
    return Some({
      kind: Editor,
      locale: @site.Japanese,
      asset_path: "/studio/index.html",
      content_type: "text/html; charset=utf-8",
      headers: [
        ("X-Robots-Tag", "noindex, nofollow"),
        ("Cache-Control", "private, no-store"),
      ],
    })
  }
  let ranked = weighted_values(accept_language)
    .mapi(fn(index, value) { (index, value) })
    .filter(fn(pair) { pair.1.quality > 0 })
  ranked.sort_by(fn(a, b) {
    let order = b.1.quality.compare(a.1.quality)
    if order == 0 {
      a.0.compare(b.0)
    } else {
      order
    }
  })
  let languages = ranked.filter_map(fn(pair) {
    normalize_language(pair.1.value)
  })
  let query = match query {
    Some("en") | Some("ja") => query
    _ => if @site.japanese_path(path) { Some("ja") } else { None }
  }
  let locale = @site.resolve_locale(query, None, languages)
  let markdown = prefers_markdown(accept)
  Some({
    kind: Home,
    locale,
    asset_path: (if locale == @site.Japanese { "/ja" } else { "" }) +
    "/index." +
    (if markdown { "md" } else { "html" }),
    content_type: (if markdown { "text/markdown" } else { "text/html" }) +
    "; charset=utf-8",
    headers: [
      ("Content-Language", @site.locale_name(locale)),
      ("Vary", "Accept, Accept-Language"),
      ("Cache-Control", "public, max-age=0, must-revalidate"),
    ],
  })
}

///|
pub fn merge_vary(existing : String, extra : String) -> String {
  let values = []
  let seen = Set([])
  for header in [existing, extra] {
    for entry in header.split(",") {
      let value = @editor.trim_text(entry.to_owned()).to_owned()
      if !seen.contains(value) {
        seen.add(value)
        values.push(value)
      }
    }
  }
  values.join(", ")
}
