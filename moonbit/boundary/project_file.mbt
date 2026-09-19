///|
pub fn bounded_utf8_size(text : String, limit : Int) -> Int {
  if text.length() > limit {
    return limit + 1
  }
  if text.is_empty() {
    return 0
  }
  let encoder = @core.new(@core.global_this()._get("TextEncoder"), [])
  let scratch = @core.new(@core.global_this()._get("Uint8Array"), [
    @core.any(65536),
  ])
  let mut offset = 0
  let mut bytes = 0
  while offset < text.length() {
    // encodeInto stops before a partial code point. Its read count is UTF-16,
    // so surrogate pairs straddling the scratch buffer remain intact.
    let encoded = encoder._call("encodeInto", [
      @core.any(text[offset:].to_owned()),
      scratch,
    ])
    offset += (encoded._get("read").cast() : Int)
    bytes += (encoded._get("written").cast() : Int)
    if bytes > limit {
      return limit + 1
    }
  }
  bytes
}

///|
pub fn parse_project_file(text : String) -> @core.Any {
  if bounded_utf8_size(text, 134217728) > 134217728 {
    @core.throw_error(
      "プロジェクトファイルは 128 MB 以下にしてください。",
    )
    return @core.undefined()
  }
  let value = @core.throwable(fn() {
    @core.global_this()
    ._get("JSON")
    ._call("parse", [
      @core.any(text),
      @core.any(fn(key : String, value : @core.Any) {
        if key == "__proto__" || key == "constructor" || key == "prototype" {
          @core.throw_error("Reserved key")
        }
        value
      }),
    ])
  }) catch {
    _ => {
      @core.throw_error(
        "対応する Poietra プロジェクト形式の JSON を読み取れませんでした。.poietra.json ファイルを選択してください。",
      )
      return @core.undefined()
    }
  }
  let parsed = parse_file_field(value, project_file_field) catch {
    _ => {
      @core.throw_error(
        "このファイルは対応する Poietra プロジェクト形式ではありません。",
      )
      return @core.undefined()
    }
  }
  let project : @scene.Project = {
    version: parsed._get("version").cast(),
    name: parsed._get("name").cast(),
    sceneOrder: decode_array(parsed._get("sceneOrder"), fn(id) { id.cast() }),
    scenes: decode_map(parsed._get("scenes"), decode_Scene),
  }
  if !@editor.valid_project_references(project) {
    @core.throw_error(
      "シーン、オブジェクト、アニメーションの参照や時間が正しくありません。",
    )
  }
  parsed
}
