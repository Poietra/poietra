///|
fn write_scalar(value : @plan.Scalar) -> @core.Any {
  match value {
    Number(value) => @core.any(value)
    Text(value) => @core.any(value)
    Boolean(value) => @core.any(value)
  }
}

///|
fn write_value(value : @plan.Value) -> @core.Any {
  match value {
    ScalarValue(value) => write_scalar(value)
    EasingValue(value) => @boundary.write_easing(value)
    PathValue(value) =>
      match value {
        Some(value) => @boundary.write_bezier(value)
        None => @core.null()
      }
    TimingValue(value) =>
      match value {
        Some(value) => @boundary.write_timing(value)
        None => @core.null()
      }
    StateValue(value) => @boundary.write_object_state(value)
    ObjectValue(value) => @boundary.write_scene_object(value)
    TrackValue(value, fields) => {
      let output = @boundary.write_track(value)
      restore_timing_fields(output, value, fields)
      output
    }
    CompositionValue(value) => @boundary.write_composition(value)
    TransitionValue(value, fields) => {
      let output = @boundary.write_transition(value)
      for id, keys in fields {
        restore_timing_fields(
          output._get("tracks")._get(id),
          value.tracks[id],
          keys,
        )
      }
      output
    }
  }
}

///|
fn precondition(
  doc : @core.Any,
  path : Array[String],
  yjs : @core.Any,
) -> @core.Any {
  if !valid_path(path) {
    return fail("編集対象が無効です。")
  }
  let expected = value(doc, path, yjs)
  @core.from_entries([
    ("path", @core.any(FixedArray::from_array(path[:]))),
    (
      "expected",
      if @core.is_nullish(expected) {
        @core.null()
      } else {
        expected
      },
    ),
    ("existed", @core.any(!@core.is_undefined(expected))),
    ("parentIdentity", parent_identity(doc, path, yjs)),
  ])
}

///|
pub fn compile_proposal(
  doc : @core.Any,
  project : @core.Any,
  scene_id : String,
  raw : @core.Any,
  yjs : @core.Any,
) -> @core.Any {
  let raw_operations : FixedArray[@core.Any] = raw._get("operations").cast()
  if raw_operations
    .iter()
    .any(fn(operation) {
      same_identity(operation._get("action"), @core.any("generateImage"))
    }) {
    return fail("画像の生成が完了していません。")
  }
  let input = @schemas.parse_resolved_proposal(raw)
  let native_operations : FixedArray[@core.Any] = input
    ._get("operations")
    .cast()
  let operations = native_operations.iter().map(read_operation).to_array()
  let scenes = project._get("scenes")
  if !owns(scenes, scene_id) {
    return fail("Scene が見つかりません。")
  }
  let original = scenes._get(scene_id)
  let base = ["scenes", scene_id]
  let raw_compositions = shared(doc, base + ["compositions"], yjs)
  let raw_order = shared(doc, base + ["compositionOrder"], yjs)
  if !instance_of(raw_compositions, yjs._get("Map")) ||
    !instance_of(raw_order, yjs._get("Array")) {
    return fail("Composition が見つかりません。")
  }
  let source = read_source(original, doc, base, raw_compositions, yjs)
  let plan = @plan.compile(source, operations, @boundary.new_id) catch {
    @plan.CompileError(message) => fail(message)
  }
  let unique : Map[String, (Array[String], @core.Any)] = Map([])
  let ordered : Array[String] = []
  for change in plan.changes {
    let path = base + change.path
    let key = path_key(path)
    if !unique.contains(key) {
      ordered.push(key)
    }
    unique[key] = (path, write_value(change.value))
  }
  let changes = []
  for key in ordered {
    let (path, next) = unique[key]
    if !same_value(value(doc, path, yjs), next) {
      let change = precondition(doc, path, yjs)
      change._set("value", next)
      changes.push(change)
    }
  }
  let seen : Set[String] = Set([])
  let guards = []
  for path in plan.guards {
    let path = base + path
    let key = path_key(path)
    if !seen.contains(key) {
      seen.add(key)
      guards.push(precondition(doc, path, yjs))
    }
  }
  let result = @core.from_entries([
    ("id", @core.any(@boundary.new_id("proposal"))),
    ("message", input._get("message")),
    ("changes", @core.any(FixedArray::from_array(changes[:]))),
    ("guards", @core.any(FixedArray::from_array(guards[:]))),
    (
      "count",
      @core.any(if changes.is_empty() { 0 } else { operations.length() }),
    ),
  ])
  if !plan.appended.is_empty() {
    let append = @core.from_entries([
      ("sceneId", @core.any(scene_id)),
      ("compositionIds", @core.any(FixedArray::from_array(plan.appended[:]))),
      ("orderIdentity", @core.any(array_identity(raw_order, yjs))),
    ])
    result._set(
      "compositionAppends",
      @core.any(([append] : FixedArray[@core.Any])),
    )
  }
  validate_proposal_for_apply(doc, result, yjs)
  result
}

///|
fn restore_timing_fields(
  output : @core.Any,
  track : @scene.Track,
  fields : Array[@scene.PropertyChannel],
) -> Unit {
  // A cleared override and an absent override evaluate alike, but preserve the
  // explicit reset in new shared records and portable proposal payloads.
  for channel in fields {
    if @scene.timing_override(track, channel) is None {
      output._set(
        @editor.property_channel_name(channel) + "Timing",
        @core.null(),
      )
    }
  }
}
