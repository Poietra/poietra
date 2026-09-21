///|
pub(all) suberror InvalidProjectFile {
  InvalidProjectFile(String)
}

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
fn decode_file(text : String) -> (@core.Any, @scene.Project) raise {
  if bounded_utf8_size(text, 134217728) > 134217728 {
    raise InvalidProjectFile(
      "プロジェクトファイルは 128 MB 以下にしてください。",
    )
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
    _ =>
      raise InvalidProjectFile(
        "対応する Poietra プロジェクト形式の JSON を読み取れませんでした。.poietra.json ファイルを選択してください。",
      )
  }
  let parsed = parse_file_field(value, project_file_field) catch {
    _ =>
      raise InvalidProjectFile(
        "このファイルは対応する Poietra プロジェクト形式ではありません。",
      )
  }
  let project : @scene.Project = {
    version: parsed._get("version").cast(),
    name: parsed._get("name").cast(),
    sceneOrder: decode_array(parsed._get("sceneOrder"), fn(id) { id.cast() }),
    scenes: decode_map(parsed._get("scenes"), decode_Scene),
  }
  if !@scene.valid_project_references(project) {
    raise InvalidProjectFile(
      "シーン、オブジェクト、アニメーションの参照や時間が正しくありません。",
    )
  }
  (parsed, project)
}

///|
pub fn parse(text : String) -> @scene.Project raise {
  decode_file(text).1
}

///|
pub fn parse_project_file(text : String) -> @core.Any {
  decode_file(text).0 catch {
    InvalidProjectFile(message) => {
      @core.throw_error(message)
      @core.undefined()
    }
    error => {
      @core.throw_error(error.to_string())
      @core.undefined()
    }
  }
}
