///|
fn escape(value : String) -> String {
  let out = StringBuilder()
  for char in value.iter() {
    match char {
      '&' => out.write_string("&amp;")
      '<' => out.write_string("&lt;")
      '>' => out.write_string("&gt;")
      '"' => out.write_string("&quot;")
      _ => out.write_char(char)
    }
  }
  out.to_string()
}

///|
fn link(label : String, href : String) -> String {
  "<a href=\"" + escape(href) + "\">" + escape(label) + "</a>"
}

///|
fn availability(locale : @site.Locale) -> String {
  t(
    locale, "Self-hosted HTTP API · Local stdio MCP", "セルフホスト HTTP API · ローカル stdio MCP",
  )
}

///|
fn block_html(block : Block) -> String {
  match block {
    Paragraph(text) => "<p>" + escape(text) + "</p>"
    Code(language, source) =>
      "<div class=\"code-block\"><span class=\"code-language\">" +
      escape(language) +
      "</span><pre tabindex=\"0\" aria-label=\"" +
      escape(language) +
      " code\"><code>" +
      escape(source) +
      "</code></pre></div>"
    Items(items) =>
      "<ul>" +
      items.map(fn(item) { "<li>" + escape(item) + "</li>" }).join("") +
      "</ul>"
    Links(items) =>
      "<ul class=\"resource-links\">" +
      items.map(fn(item) { "<li>" + link(item.0, item.1) + "</li>" }).join("") +
      "</ul>"
    Endpoints =>
      "<div class=\"endpoint-list\">" +
      @api.endpoints()
      .map(fn(endpoint) {
        "<div class=\"endpoint\"><code class=\"method\">" +
        endpoint.method_ +
        "</code><code>" +
        escape(endpoint.path) +
        "</code><p>" +
        escape(endpoint.summary) +
        "</p></div>"
      })
      .join("") +
      "</div>"
  }
}

///|
fn markdown(locale : @site.Locale) -> String {
  let result = [
    "# Poietra for developers",
    description(locale),
    "**" + availability(locale) + "**",
    t(
      locale, "poietra.com serves documentation and schemas. Start the renderer where your agent runs; there is no hosted render API or remote MCP endpoint.",
      "poietra.com はドキュメントとスキーマを配信します。エージェントの実行環境で描画サービスを起動してください。ホストされた描画 API やリモート MCP は未提供です。",
    ),
    "- [OpenAPI](https://poietra.com/openapi.json)\n- [Project schema](https://poietra.com/schemas/project.json)\n- [Starter project](https://poietra.com/examples/hello.poietra.json)\n- [MCP configuration example](https://poietra.com/developers/mcp-config.json)",
  ]
  for section in sections(locale) {
    result.push("## " + section.title)
    for block in section.blocks {
      result.push(
        match block {
          Paragraph(text) => text
          Code(language, source) => "~~~" + language + "\n" + source + "\n~~~"
          Items(items) => items.map(fn(item) { "- " + item }).join("\n")
          Links(items) =>
            items
            .map(fn(item) {
              "- [" +
              item.0 +
              "](" +
              (if item.1.has_prefix("/") { "https://poietra.com" } else { "" }) +
              item.1 +
              ")"
            })
            .join("\n")
          Endpoints =>
            @api.endpoints()
            .map(fn(endpoint) {
              "- " +
              endpoint.method_ +
              " " +
              endpoint.path +
              " — " +
              endpoint.summary
            })
            .join("\n")
        },
      )
    }
  }
  result.join("\n\n") + "\n"
}

///|
fn page(locale : @site.Locale, styles : String) -> String {
  let name = @site.locale_name(locale)
  let prefix = if locale == @site.Japanese { "/ja" } else { "" }
  let path = prefix + "/developers/"
  let canonical = "https://poietra.com" + path
  let schema : Json = {
    "@context": "https://schema.org",
    "@type": "TechArticle",
    "headline": "Poietra for developers",
    "description": Json(description(locale)),
    "url": Json(canonical),
    "inLanguage": Json(name),
    "about": { "@type": "SoftwareApplication", "name": "Poietra" },
  }
  let content = sections(locale)
  let nav = content
    .map(fn(section) { link(section.title, "#" + section.id) })
    .join("")
  let body = content
    .map(fn(section) {
      "<section id=\"" +
      section.id +
      "\" aria-labelledby=\"" +
      section.id +
      "-title\">" +
      "<h2 id=\"" +
      section.id +
      "-title\">" +
      escape(section.title) +
      "</h2>" +
      section.blocks.map(block_html).join("\n") +
      "</section>"
    })
    .join("\n")
  [
    "<!doctype html><html lang=\"" + name + "\"><head>",
    "<meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">",
    "<title>Poietra — API &amp; MCP</title><meta name=\"description\" content=\"" +
    escape(description(locale)) +
    "\">",
    "<meta name=\"theme-color\" content=\"#191920\"><link rel=\"icon\" type=\"image/svg+xml\" href=\"/poietra.svg\">",
    "<link rel=\"canonical\" href=\"" + canonical + "\">",
    "<link rel=\"alternate\" hreflang=\"en\" href=\"https://poietra.com/developers/\">",
    "<link rel=\"alternate\" hreflang=\"ja\" href=\"https://poietra.com/ja/developers/\">",
    "<link rel=\"alternate\" hreflang=\"x-default\" href=\"https://poietra.com/developers/\">",
    "<link rel=\"alternate\" type=\"text/markdown\" href=\"" +
    path +
    "index.md\">",
    "<link rel=\"service-desc\" type=\"application/json\" href=\"/openapi.json\">",
    "<meta property=\"og:title\" content=\"Poietra — API &amp; MCP\"><meta property=\"og:description\" content=\"" +
    escape(description(locale)) +
    "\"><meta property=\"og:url\" content=\"" +
    canonical +
    "\">",
    styles,
    "<link rel=\"stylesheet\" href=\"/developers.css\">",
    "<script type=\"application/ld+json\">" +
    schema.stringify() +
    "</script></head>",
    "<body class=\"developer-page\"><a class=\"skip-link\" href=\"#main\">" +
    t(locale, "Skip to content", "本文へ移動") +
    "</a>",
    "<header class=\"developer-header wrap\"><a class=\"brand\" href=\"" +
    prefix +
    "/\"><img src=\"/poietra.svg\" width=\"32\" height=\"32\" alt=\"\">Poietra<span> / developers</span></a>",
    "<nav aria-label=\"" +
    t(locale, "Main navigation", "メインナビゲーション") +
    "\">" +
    link(
      t(locale, "日本語", "English"),
      if locale == @site.Japanese {
        "/developers/?lang=en"
      } else {
        "/ja/developers/"
      },
    ) +
    link("GitHub", "https://github.com/Poietra/poietra") +
    link(t(locale, "Open studio", "Studio を開く"), "/studio") +
    "</nav></header>",
    "<main id=\"main\" class=\"wrap\" tabindex=\"-1\"><div class=\"developer-hero\">",
    "<p class=\"eyebrow\">API &amp; MCP</p><h1>" +
    t(
      locale, "Your agent.<br>In motion.", "エージェントから、<br>動画をつくる。",
    ) +
    "</h1>",
    "<p class=\"lead\">" + escape(description(locale)) + "</p>",
    "<div class=\"hero-actions\"><a class=\"primary-link\" href=\"/openapi.json\">OpenAPI JSON <span aria-hidden=\"true\">↗</span></a>" +
    link(t(locale, "Connect MCP", "MCP を接続"), "#mcp") +
    link("Markdown", path + "index.md") +
    "</div>",
    "<p class=\"availability\"><span aria-hidden=\"true\"></span>" +
    availability(locale) +
    "</p>",
    "<div class=\"file-flow\" aria-label=\"" +
    t(locale, "Input and output", "入力と出力") +
    "\"><code>project.poietra.json</code><span aria-hidden=\"true\">→</span><code>SVG · PNG · MP4</code></div></div>",
    "<div class=\"docs-layout\"><aside><nav aria-label=\"" +
    t(locale, "On this page", "このページの内容") +
    "\">" +
    nav +
    "<a href=\"/llms.txt\">llms.txt</a></nav><p>" +
    t(
      locale, "Documentation is hosted here.<br>Rendering runs on your machine.",
      "ここでは仕様を公開しています。<br>描画は手元の環境で実行します。",
    ) +
    "</p></aside><article>" +
    body +
    "</article></div></main>",
    "<footer class=\"wrap developer-footer\"><span>Poietra — Motion, together.</span>" +
    link(
      t(
        locale, "Agent documentation", "エージェント向けドキュメント",
      ),
      path + "index.md",
    ) +
    "</footer></body></html>",
  ].join("\n")
}

///|
pub fn files(styles : String) -> @core.Any {
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
    let prefix = if locale == @site.Japanese { "ja/" } else { "" }
    add(prefix + "developers/index.html", page(locale, styles))
    add(prefix + "developers/index.md", markdown(locale))
  }
  add("openapi.json", @api.openapi_json("http://127.0.0.1:8799"))
  add("schemas/project.json", @api.project_schema_json())
  add("examples/hello.poietra.json", @api.example_json())
  add("developers/mcp-config.json", mcp_config())
  @core.any(FixedArray::from_array(result[:]))
}
