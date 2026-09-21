///|
pub fn landing_copy(locale : String) -> @core.Any {
  // One-time adapter for build-time consumers, never part of frame evaluation.
  @core.json_parse(
    @site.landing_copy(@site.locale(locale).unwrap_or(English))
    .to_json()
    .stringify(),
  )
}

///|
pub fn render_markdown(locale : String) -> String {
  let locale = @site.locale(locale).unwrap_or(English)
  let c = @site.landing_copy(locale)
  [
    "# Poietra — Motion, together.",
    @site.page_copy(locale).description,
    c.introduction,
    "## " + c.detailTitle.join(" "),
    c.detailDescription,
    "## " + c.sharingTitle,
    c.sharingDescription,
    "## " + c.aiTitle,
    c.aiBeforeMention + "@codex" + c.aiAfterMention,
    "## " + c.mediaTitle,
    c.mediaDescription,
    "## Links",
    "- [Open the studio](https://poietra.com/studio)\n- [English homepage](https://poietra.com/?lang=en)\n- [日本語](https://poietra.com/ja/)\n- [API / MCP](https://poietra.com/developers/)\n- [OpenAPI](https://poietra.com/openapi.json)\n- [Source code](https://github.com/Poietra/poietra)",
  ].join("\n\n") +
  "\n"
}
