///|
pub fn write_geometry_point(value : @scene.GeometryPoint) -> @core.Any {
  @project_codec.encode_GeometryPoint(value)
}

///|
pub fn write_geometry_vector(value : @scene.GeometryVector) -> @core.Any {
  @project_codec.encode_GeometryVector(value)
}

///|
pub fn write_geometry_angle(value : @scene.GeometryAngle) -> @core.Any {
  @project_codec.encode_GeometryAngle(value)
}

///|
pub fn merge_geometry_patch(
  current : @core.Any,
  patch : @core.Any,
) -> @core.Any {
  if @core.is_nullish(patch) ||
    @core.typeof_(patch) != "object" ||
    @core.is_array(patch) {
    @core.throw_error("幾何の編集内容が不正です。")
  }
  if @core.is_nullish(current) {
    @core.throw_error("数学図を選択してください。")
  }
  let next = merge_values(current, @core.new_object())
  for field in @core.object_keys(patch) {
    if field == "version" {
      next._set(field, patch._get(field))
      continue
    }
    if !["points", "vectors", "angles"].contains(field) {
      @core.throw_error("対応していない幾何の項目です。")
    }
    let entries = patch._get(field)
    if @core.is_nullish(entries) ||
      @core.typeof_(entries) != "object" ||
      @core.is_array(entries) {
      @core.throw_error("要素の編集内容が不正です。")
    }
    let existing = current._get(field)
    let values = merge_values(existing, @core.new_object())
    for id in @core.object_keys(entries) {
      if ["__proto__", "constructor", "prototype"].contains(id) {
        @core.throw_error("要素のIDが不正です。")
      }
      let value = entries._get(id)
      if @core.is_nullish(value) ||
        @core.typeof_(value) != "object" ||
        @core.is_array(value) {
        @core.throw_error(
          "要素は削除フラグで取り除いてください。",
        )
      }
      let fields = match field {
        "points" => ["kind", "x", "y", "from", "to", "label", "deleted"]
        "vectors" => ["from", "to", "label", "deleted"]
        _ => ["from", "vertex", "to", "label", "deleted"]
      }
      if @core.object_keys(value).iter().any(fn(key) { !fields.contains(key) }) {
        @core.throw_error("対応していない要素の項目です。")
      }
      let prior = if @core.object_keys(existing).contains(id) {
        existing._get(id)
      } else {
        @core.undefined()
      }
      values._set(id, merge_values(prior, value))
    }
    next._set(field, values)
  }
  @project_codec.read_geometry_definition(next) |> ignore
  next
}

///|
/// Validate the complete immutable candidate, then publish only intended leaves.
pub fn geometry_patch_changes(
  current : @core.Any,
  patch : @core.Any,
  base : FixedArray[String],
) -> Array[@core.Any] {
  let next = merge_geometry_patch(current, patch)
  let changes : Array[@core.Any] = []
  for field in @core.object_keys(patch) {
    if field == "version" {
      changes.append(
        changes_for(base, @core.from_entries([("version", patch._get(field))])),
      )
      continue
    }
    let old = current._get(field)
    for id in @core.object_keys(patch._get(field)) {
      let path = FixedArray::makei(base.length() + 2, fn(i) {
        if i < base.length() {
          base[i]
        } else if i == base.length() {
          field
        } else {
          id
        }
      })
      if @core.object_keys(old).contains(id) {
        changes.append(changes_for(path, patch._get(field)._get(id)))
      } else {
        changes.push(
          @core.from_entries([
            ("path", @core.any(path)),
            ("value", next._get(field)._get(id)),
          ]),
        )
      }
    }
  }
  changes
}
