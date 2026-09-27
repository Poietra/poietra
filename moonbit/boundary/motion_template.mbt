///|
pub fn motion_project(scene : @scene.Scene) -> @core.Any {
  encode_project({
    version: if scene.objects
      .values()
      .any(fn(o) { o.clipChildren == Some(true) }) {
      3
    } else {
      2
    },
    name: scene.name[:scene.name.length().min(100)].to_owned(),
    sceneOrder: [scene.id],
    scenes: Map([(scene.id, scene)]),
  })
}

///|
pub fn capture_motion(
  scene : @core.Any,
  ids : FixedArray[String],
  name : String,
) -> @core.Any {
  match
    @editor.capture_motion(
      @project_codec.decode_Scene(scene),
      ids.iter().to_array(),
      name,
    ) {
    Ok(scene) => motion_project(scene)
    Err(message) => fail(message)
  }
}

///|
fn single_motion(project : @scene.Project) -> @scene.Scene {
  if project.sceneOrder.length() != 1 {
    return fail("動きのファイルは 1 Scene にしてください。")
  }
  let scene = project.scenes[project.sceneOrder[0]]
  if scene.objects.is_empty() {
    return fail("動きのオブジェクトがありません。")
  }
  if scene.audioTracks.map(fn(t) { !t.is_empty() }).unwrap_or(false) {
    return fail(
      "独立した音声トラックを含むファイルは、Open project で開いてください。",
    )
  }
  scene
}

///|
pub fn read_motion_file(text : String) -> @scene.Scene {
  single_motion(
    @project_codec.parse(text) catch {
      error => return fail(error.to_string())
    },
  )
}

///|
pub fn replace_motion(
  scene : @scene.Scene,
  texts : Map[String, String],
  colors : Map[String, String],
) -> @scene.Scene {
  if texts.values().any(fn(text) { text.length() > 10000 }) {
    return fail("文字は 10,000 文字以内にしてください。")
  }
  if colors.values().any(fn(color) { !@assets.document_color(color) }) {
    return fail("色を #RRGGBB などの形式で指定してください。")
  }
  @editor.replace_motion(scene, texts, colors)
}

///|
pub struct PreparedMotionInsertion {
  composition : String
  objects : FixedArray[String]
  publish : () -> Unit
}

///|
pub fn validate_motion_insertion(
  target : @core.Any,
  source : @scene.Scene,
) -> Unit {
  match
    @editor.validate_motion_insertion(
      @project_codec.decode_Scene(target),
      source,
    ) {
    Ok(_) => ()
    Err(message) => fail(message)
  }
}

///|
pub fn prepare_motion_insertion(
  doc : @core.Any,
  scene_id : String,
  project : @core.Any,
  host : @core.Any,
) -> PreparedMotionInsertion {
  let source = single_motion(
    @project_codec.read_project(project) catch {
      _ =>
        return fail(
          "動きのファイルの値・参照が正しくありません。",
        )
    },
  )
  let current = current_scene(doc, scene_id, host)
  let raw = get_value(doc, ["scenes", scene_id], host)
  let effective = @project_codec.decode_Scene(current.scene)
  // Retained containers receive hidden initial states too, so Undo of deletion
  // cannot reveal the inserted motion in an earlier Composition.
  let target = {
    ..effective,
    compositions: @project_codec.decode_map(raw._get("compositions"), fn(
      value,
    ) {
      @project_codec.decode_Composition(value)
    }),
  }
  let plan = match @editor.insert_motion(target, source, new_id) {
    Ok(plan) => plan
    Err(message) => return fail(message)
  }
  let order = append_parent(
    doc,
    ["scenes", scene_id, "compositionOrder"],
    host._get("Array"),
    host,
  )
  let compositions = append_parent(
    doc,
    ["scenes", scene_id, "compositions"],
    host._get("Map"),
    host,
  )
  let transitions = append_parent(
    doc,
    ["scenes", scene_id, "transitions"],
    host._get("Map"),
    host,
  )
  let retained = map_get(compositions, plan.source_id)
  let writes : Array[(@core.Any, String, @core.Any)] = []
  for tid in @core.object_keys(raw._get("transitions")) {
    if target.transitions.contains(tid) {
      continue
    }
    let transition = raw._get("transitions")._get(tid)
    let parent = append_parent(
      doc,
      ["scenes", scene_id, "transitions", tid, "tracks"],
      host._get("Map"),
      host,
    )
    for addition in plan.objects {
      let track = @scene.default_track(
        addition.object.id,
        transition._get("duration").cast(),
      )
      writes.push(
        (
          parent,
          addition.object.id,
          to_shared(@project_codec.encode_Track(track), host),
        ),
      )
    }
  }
  for change in object_insertion_changes(scene_id, plan.objects) {
    let path = string_array(change._get("path"))
    if path == ["version"] {
      continue
    }
    let parent = append_parent(
      doc,
      FixedArray::from_array(path[:path.length() - 1]),
      host._get("Map"),
      host,
    )
    writes.push(
      (parent, path.last().unwrap(), to_shared(change._get("value"), host)),
    )
  }
  for value in plan.compositions {
    writes.push(
      (
        compositions,
        value.id,
        to_shared(@project_codec.encode_Composition(value), host),
      ),
    )
  }
  for value in plan.transitions {
    writes.push(
      (
        transitions,
        value.id,
        to_shared(@project_codec.encode_Transition(value), host),
      ),
    )
  }
  let ids = FixedArray::from_array(plan.compositions.map(fn(c) { c.id })[:])
  // All parents and detached payloads are ready before upgrading or publishing.
  upgrade_format_to(
    doc,
    if source.objects.values().any(fn(o) { o.clipChildren == Some(true) }) {
      3
    } else {
      2
    },
  )
  {
    composition: ids[0],
    objects: FixedArray::from_array(plan.objects.map(fn(o) { o.object.id })[:]),
    publish: fn() {
      if is_instance(retained, host._get("Map")) &&
        truthy(map_get(retained, "deleted")) {
        map_set(retained, "deleted", @core.any(false))
      }
      for (parent, key, value) in writes {
        map_set(parent, key, value)
      }
      order._call("push", [@core.any(ids)]) |> ignore
    },
  }
}
