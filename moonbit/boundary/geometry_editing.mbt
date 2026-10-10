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
fn merge_element_patch(
  current : @core.Any,
  patch : @core.Any,
  family : String,
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
    let collections = if family == "network" {
      ["nodes", "edges"]
    } else {
      ["points", "vectors", "angles"]
    }
    if !collections.contains(field) {
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
        "nodes" => ["x", "y", "label", "deleted"]
        "edges" =>
          ["from", "to", "label", "directed", "weight", "bend", "deleted"]
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
  if family == "network" {
    @project_codec.read_network_definition(next) |> ignore
  } else {
    @project_codec.read_geometry_definition(next) |> ignore
  }
  next
}

///|
/// Validate the complete immutable candidate, then publish only intended leaves.
fn element_patch_changes(
  current : @core.Any,
  patch : @core.Any,
  base : FixedArray[String],
  family : String,
) -> Array[@core.Any] {
  let next = merge_element_patch(current, patch, family)
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

///|
pub fn merge_geometry_patch(
  current : @core.Any,
  patch : @core.Any,
) -> @core.Any {
  merge_element_patch(current, patch, "geometry")
}

///|
pub fn merge_network_patch(current : @core.Any, patch : @core.Any) -> @core.Any {
  merge_element_patch(current, patch, "network")
}

///|
pub fn geometry_patch_changes(
  current : @core.Any,
  patch : @core.Any,
  base : FixedArray[String],
) -> Array[@core.Any] {
  element_patch_changes(current, patch, base, "geometry")
}

///|
pub fn network_patch_changes(
  current : @core.Any,
  patch : @core.Any,
  base : FixedArray[String],
) -> Array[@core.Any] {
  element_patch_changes(current, patch, base, "network")
}

///|
pub fn write_network_node(value : @scene.NetworkNode) -> @core.Any {
  @project_codec.encode_NetworkNode(value)
}

///|
pub fn write_network_edge(value : @scene.NetworkEdge) -> @core.Any {
  @project_codec.encode_NetworkEdge(value)
}

///|
pub fn write_surface(value : @scene.SurfaceDefinition) -> @core.Any {
  @project_codec.encode_SurfaceDefinition(value)
}

///|
pub fn merge_surface_patch(current : @core.Any, patch : @core.Any) -> @core.Any {
  if @core.is_nullish(current) ||
    @core.is_nullish(patch) ||
    @core.typeof_(patch) != "object" ||
    @core.is_array(patch) {
    @core.throw_error("3D曲面の編集内容が不正です。")
  }
  let fields = @core.object_keys(write_surface(@scene.default_surface()))
  if @core.object_keys(patch).iter().any(fn(key) { !fields.contains(key) }) {
    @core.throw_error("対応していない曲面の項目です。")
  }
  let next = merge_values(current, patch)
  @project_codec.read_surface_definition(next) |> ignore
  next
}
