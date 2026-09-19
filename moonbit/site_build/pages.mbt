///|
fn replace(source : String, pattern : String, replacement : String) -> String {
  @core.any(source)
  ._call("replace", [@core.any(pattern), @core.any(fn() { replacement })])
  .cast()
}

///|
fn escaped(value : String) -> String {
  let out = StringBuilder()
  for char in value.iter() {
    match char {
      '&' => out.write_string("&amp;")
      '"' => out.write_string("&quot;")
      '<' => out.write_string("&lt;")
      _ => out.write_char(char)
    }
  }
  out.to_string()
}

///|
fn entries(value : @core.Any) -> Array[String] {
  if @core.is_nullish(value) {
    []
  } else {
    (value.cast() : FixedArray[String]).iter().to_array()
  }
}

///|
fn styles(manifest : @core.Any, root : @core.Any) -> Array[String] {
  let seen = Set([])
  let included = Set([])
  let result = []
  fn visit(entry : @core.Any) -> Unit {
    for css in entries(entry._get("css")) {
      if !included.contains(css) {
        included.add(css) |> ignore
        result.push(css)
      }
    }
    for key in entries(entry._get("imports")) {
      if !seen.contains(key) {
        seen.add(key) |> ignore
        visit(manifest._get(key))
      }
    }
  }
  visit(root)
  result
}

///|
fn home_head(
  locale : @site.Locale,
  links : String,
  home_file : String,
) -> String {
  let name = @site.locale_name(locale)
  let prefix = if locale == Japanese { "ja/" } else { "" }
  let canonical = "https://poietra.com/" + prefix
  let schema = @core.from_entries([
    ("@context", @core.any("https://schema.org")),
    ("@type", @core.any("WebApplication")),
    ("name", @core.any("Poietra")),
    ("url", @core.any(canonical)),
    ("description", @core.any(@site.page_copy(locale).description)),
    ("applicationCategory", @core.any("MultimediaApplication")),
    ("operatingSystem", @core.any("Web browser")),
    ("inLanguage", @core.any(name)),
    ("image", @core.any("https://poietra.com/studio-preview.png")),
    (
      "featureList",
      @core.any(
        (
          [
            "Real-time collaborative editing", "Editable animation and Bézier paths",
            "AI-assisted editing", "Image, audio and video media", "MP4 and WebM export",
          ] : FixedArray[String]),
      ),
    ),
  ])
  let json : String = @core.global_this()
    ._get("JSON")
    ._call("stringify", [schema])
    ._call("replaceAll", [@core.any("<"), @core.any("\\u003c")])
    .cast()
  links +
  "\n" +
  [
    "<link rel=\"modulepreload\" crossorigin href=\"/" +
    escaped(home_file) +
    "\" />",
    "<link rel=\"canonical\" href=\"" + canonical + "\" />",
    "<link rel=\"alternate\" hreflang=\"en\" href=\"https://poietra.com/\" />",
    "<link rel=\"alternate\" hreflang=\"ja\" href=\"https://poietra.com/ja/\" />",
    "<link rel=\"alternate\" hreflang=\"x-default\" href=\"https://poietra.com/\" />",
    "<link rel=\"alternate\" type=\"text/markdown\" href=\"/" +
    prefix +
    "index.md\" />",
    "<meta property=\"og:url\" content=\"" + canonical + "\" />",
    "<meta property=\"og:locale\" content=\"" +
    (if locale == Japanese { "ja_JP" } else { "en_US" }) +
    "\" />",
    "<script type=\"application/ld+json\">" + json + "</script>",
  ].join("\n    ")
}

///|
fn home_page(
  shell : String,
  locale : @site.Locale,
  head : String,
  html : String,
) -> String {
  let name = @site.locale_name(locale)
  let pattern = @core.new(@core.global_this()._get("RegExp"), [
    @core.any(
      "(<meta (?:name=\"description\"|property=\"og:description\") content=\")[^\"]*\"",
    ),
    @core.any("g"),
  ])
  let described : String = @core.any(shell)
    ._call("replace", [
      pattern,
      @core.any(fn(_match : String, prefix : String) {
        prefix + escaped(@site.page_copy(locale).description) + "\""
      }),
    ])
    .cast()
  let page = replace(
    described,
    "<html lang=\"en\">",
    "<html lang=\"" + name + "\">",
  )
  let page = replace(page, "</head>", head + "\n</head>")
  let page = replace(page, "<body>", "<body data-page=\"home\">")
  replace(
    page,
    "<div id=\"root\"></div>",
    "<div id=\"root\" data-locale=\"" + name + "\">" + html + "</div>",
  )
}

///|
pub fn render_files(
  shell : String,
  manifest : @core.Any,
  render_home : @core.Any,
  markdown : @core.Any,
) -> @core.Any {
  let home = manifest._get("src/home.js")
  if @core.is_nullish(home) {
    @core.throw_error("Homepage entry is missing from the build manifest")
  }
  let links = styles(manifest, home)
    .map(fn(css) {
      "<link rel=\"stylesheet\" crossorigin href=\"/" + escaped(css) + "\" />"
    })
    .join("\n")
  let result = []
  let add = fn(path : String, content : String) {
    result.push(
      @core.from_entries([
        ("path", @core.any(path)),
        ("content", @core.any(content)),
      ]),
    )
  }
  for locale in [@site.English, @site.Japanese] {
    let name = @site.locale_name(locale)
    let rendered = render_home._invoke([@core.any(name)])
    let prefix = if locale == Japanese { "ja/" } else { "" }
    add(
      prefix + "index.html",
      home_page(
        shell,
        locale,
        home_head(locale, links, home._get("file").cast()),
        rendered._get("html").cast(),
      ),
    )
    add(prefix + "index.md", markdown._invoke([@core.any(name)]).cast())
  }
  add(
    "studio/index.html",
    replace(
      replace(
        shell, "</head>", "<meta name=\"robots\" content=\"noindex, nofollow\" />\n</head>",
      ),
      "<body>",
      "<body data-page=\"editor\">",
    ),
  )
  add(
    "404.html", "<!doctype html><html lang=\"en\"><meta charset=\"utf-8\"><meta name=\"robots\" content=\"noindex\"><title>Page not found — Poietra</title><h1>Page not found</h1><a href=\"/\">Poietra home</a></html>",
  )
  @core.any(FixedArray::from_array(result[:]))
}
