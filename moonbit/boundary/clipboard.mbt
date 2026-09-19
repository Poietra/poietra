///|
fn read_clipboard(value : @core.Any) -> @editor.ObjectClipboard {
  {
    objects: decode_array(value._get("objects"), decode_SceneObject),
    states: decode_map(value._get("states"), decode_ObjectState),
  }
}

///|
fn write_clipboard(value : @editor.ObjectClipboard) -> @core.Any {
  @core.from_entries([
    ("objects", encode_array(value.objects, encode_SceneObject)),
    ("states", encode_map(value.states, encode_ObjectState)),
  ])
}

///|
pub fn copy_objects(
  scene : @core.Any,
  composition_id : String,
  ids : FixedArray[String],
) -> @core.Any {
  let composition = scene._get("compositions")._get(composition_id)
  let objects = scene._get("objects")
  let states = if truthy(composition) {
    composition._get("states")
  } else {
    @core.new_object()
  }
  let ordered = ordered_objects(scene)
  let chosen = @editor.copied_object_ids(
    Array::makei(ordered.length(), fn(i) { ordered[i]._get("id").cast() }),
    @core.object_keys(states),
    Array::makei(ids.length(), fn(i) { ids[i] }),
  )
  let copied = Map([])
  let metadata = []
  for id in chosen {
    let state = decode_ObjectState(states._get(id))
    let object = decode_SceneObject(objects._get(id))
    let retained = object.parentId
      .map(fn(parent) { chosen.contains(parent) })
      .unwrap_or(true)
    copied[id] = if retained {
      state
    } else {
      state.with_matrix(object_matrix(scene, composition_id, id))
    }
    metadata.push(if retained { object } else { { ..object, parentId: None, } })
  }
  write_clipboard({ objects: metadata, states: copied, })
}

///|
pub fn serialize_objects(value : @core.Any) -> String {
  let clipboard = read_clipboard(value)
  let objects = Map([])
  for object in clipboard.objects {
    objects[object.id] = object
  }
  let composition : @scene.Composition = {
    id: "clipboard",
    name: "Clipboard",
    duration: 1000.0,
    accent: "#ffffff",
    states: clipboard.states,
    deleted: None,
    incomingTransitionId: None,
  }
  let scene : @scene.Scene = {
    id: "clipboard",
    name: "Clipboard",
    width: 1280.0,
    height: 720.0,
    background: "#000000",
    objects,
    compositionOrder: ["clipboard"],
    compositions: { "clipboard": composition },
    transitions: Map([]),
    audioTracks: None,
    deleted: None,
  }
  let project : @scene.Project = {
    version: if clipboard.objects.any(fn(o) { o.parentId is Some(_) }) ||
      clipboard.states.values().any(fn(s) { s.has_transform() }) {
      2
    } else {
      1
    },
    name: "Clipboard",
    sceneOrder: ["clipboard"],
    scenes: { "clipboard": scene },
  }
  let text : String = @core.global_this()
    ._get("JSON")
    ._call("stringify", [encode_project(project)])
    .cast()
  if bounded_utf8_size(text, 1048576) > 1048576 {
    @core.throw_error(
      "一度にコピーするオブジェクトを減らしてください。",
    )
  }
  "POIETRA_OBJECTS_V1\n" + text
}

///|
pub fn parse_objects(text : String) -> @core.Any {
  let prefix = "POIETRA_OBJECTS_V1\n"
  if !text.has_prefix(prefix) {
    return @core.null()
  }
  if bounded_utf8_size(text, 1048576 + prefix.length()) >
    1048576 + prefix.length() {
    @core.throw_error(
      "一度にコピーするオブジェクトを減らしてください。",
    )
    return @core.null()
  }
  let project = parse_project_file(text[prefix.length():].to_owned())
  let scene = project._get("scenes")._get("clipboard")
  let order : FixedArray[String] = project._get("sceneOrder").cast()
  if order.length() != 1 || !truthy(scene) {
    @core.throw_error(
      "コピーしたオブジェクトを読み取れませんでした。",
    )
    return @core.null()
  }
  let compositions : FixedArray[String] = scene._get("compositionOrder").cast()
  if compositions.length() != 1 ||
    !truthy(scene._get("compositions")._get("clipboard")) ||
    !@core.object_keys(scene._get("transitions")).is_empty() {
    @core.throw_error(
      "コピーしたオブジェクトを読み取れませんでした。",
    )
    return @core.null()
  }
  let objects = ordered_objects(scene)
  let states = scene._get("compositions")._get("clipboard")._get("states")
  if objects.is_empty() {
    @core.throw_error(
      "コピーしたオブジェクトが見つかりません。",
    )
    return @core.null()
  }
  for object in objects {
    if !truthy(states._get(object._get("id").cast())) {
      @core.throw_error(
        "コピーしたオブジェクトが見つかりません。",
      )
      return @core.null()
    }
  }
  @core.from_entries([("objects", @core.any(objects)), ("states", states)])
}

///|
pub fn paste_object_changes(
  scene : @core.Any,
  composition_id : String,
  clipboard : @core.Any,
  offset : @core.Any,
) -> @core.Any {
  let offset : Double = if @core.is_undefined(offset) {
    24.0
  } else {
    offset.cast()
  }
  let scene_id : String = scene._get("id").cast()
  let objects = scene._get("objects")
  let compositions = scene._get("compositions")
  let transitions = scene._get("transitions")
  let decoded : @editor.PasteScene = {
    objects: @core.object_keys(objects).map(fn(id) {
      let object = objects._get(id)
      (object._get("name").cast(), object._get("order").cast())
    }),
    compositions: @core.object_keys(compositions).map(fn(id) {
      compositions._get(id)._get("id").cast()
    }),
    transitions: @core.object_keys(transitions).map(fn(id) {
      let transition = transitions._get(id)
      (transition._get("id").cast(), transition._get("duration").cast())
    }),
  }
  let additions = match
    @editor.paste_objects(
      decoded,
      composition_id,
      read_clipboard(clipboard),
      offset,
      new_id,
    ) {
    Ok(additions) => additions
    Err(message) => {
      @core.throw_error(message)
      return @core.undefined()
    }
  }
  let changes = []
  let ids = []
  for addition in additions {
    let id = addition.object.id
    ids.push(id)
    changes.push(
      make_change(
        ["scenes", scene_id, "objects", id],
        encode_SceneObject(addition.object),
      ),
    )
    for (tid, track) in addition.tracks {
      changes.push(
        make_change(
          ["scenes", scene_id, "transitions", tid, "tracks", id],
          encode_Track(track),
        ),
      )
    }
    for (cid, state) in addition.states {
      changes.push(
        make_change(
          ["scenes", scene_id, "compositions", cid, "states", id],
          encode_ObjectState(state),
        ),
      )
    }
  }
  @core.from_entries([
    ("ids", @core.any(FixedArray::makei(ids.length(), fn(i) { ids[i] }))),
    (
      "changes",
      @core.any(FixedArray::makei(changes.length(), fn(i) { changes[i] })),
    ),
  ])
}
