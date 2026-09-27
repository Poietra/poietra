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
fn parse_file_json(text : String) -> @core.Any raise {
  let value = @core.throwable(fn() {
    @core.global_this()._get("JSON")._call("parse", [@core.any(text)])
  })
  // Visit every parsed key before normalization, including ignored subtrees.
  // Arrays have only index keys in JSON. Enqueue containers, not scalar leaves,
  // so the guard needs neither a parser callback per value nor recursive calls.
  let pending = [value]
  while pending.pop() is Some(current) {
    if @core.is_null(current) || @core.typeof_(current) != "object" {
      continue
    }
    if is_array(current) {
      let items : FixedArray[@core.Any] = current.cast()
      for item in items {
        if !@core.is_null(item) && @core.typeof_(item) == "object" {
          pending.push(item)
        }
      }
    } else {
      for key in @core.object_keys(current) {
        if key == "__proto__" || key == "constructor" || key == "prototype" {
          raise InvalidFileField
        }
        let item = current._get(key)
        if !@core.is_null(item) && @core.typeof_(item) == "object" {
          pending.push(item)
        }
      }
    }
  }
  value
}

///|
fn decode_file(text : String) -> (@core.Any, @scene.Project) raise {
  if bounded_utf8_size(text, 134217728) > 134217728 {
    raise InvalidProjectFile(
      "プロジェクトファイルは 128 MB 以下にしてください。",
    )
  }
  let value = parse_file_json(text) catch {
    _ =>
      raise InvalidProjectFile(
        "対応する Poietra プロジェクト形式の JSON を読み取れませんでした。.poietra.json ファイルを選択してください。",
      )
  }
  // JSON.parse produced a private tree and its keys have been checked.
  // Normalize that owned tree in place; ordinary native readers still copy.
  let parsed = parse_file_field(value, project_file_field, ownership=ParsedJson) catch {
    _ =>
      raise InvalidProjectFile(
        "このファイルは対応する Poietra プロジェクト形式ではありません。",
      )
  }
  (parsed, decode_normalized_project(parsed))
}

///|
fn decode_normalized_project(parsed : @core.Any) -> @scene.Project raise {
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
  project
}

///|
/// Native callers borrow their input; normalization must never mutate it.
pub fn read_project(value : @core.Any) -> @scene.Project raise {
  decode_normalized_project(parse_file_field(value, project_file_field))
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
