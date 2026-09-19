///|
pub fn set_project_name(store : @core.Any, name : String) -> Unit {
  let name = slice_text(name, 100)
  edit(store, [
    change(
      ["name"],
      @core.any(if name.is_empty() { "Untitled project" } else { name }),
    ),
  ])
}

///|
pub fn set_scene(store : @core.Any, scene : String, patch : @core.Any) -> Unit {
  edit(store, changes_for(["scenes", scene], patch))
}

///|
pub fn set_object(
  store : @core.Any,
  scene : String,
  id : String,
  patch : @core.Any,
) -> Unit {
  edit(store, changes_for(["scenes", scene, "objects", id], patch))
}

///|
pub fn update_state(
  store : @core.Any,
  scene_id : String,
  composition_id : String,
  id : String,
  patch : @core.Any,
  separate : Bool,
) -> Unit {
  let scene = current_scene(store, scene_id)
  let object = scene._get("objects")._get(id)
  if !truthy(object) || truthy(object._get("locked")) {
    return
  }
  let composition = scene._get("compositions")._get(composition_id)
  if !truthy(composition) {
    return
  }
  let base = ["scenes", scene_id, "compositions", composition_id, "states", id]
  if truthy(composition._get("states")._get(id)) {
    edit(store, changes_for(base, patch), separate~)
    return
  }
  let mut prior = @core.undefined()
  let compositions = scene._get("compositions")
  for cid in @core.object_keys(compositions) {
    let state = compositions._get(cid)._get("states")._get(id)
    if truthy(state) {
      prior = state
      break
    }
  }
  let state = if truthy(prior) {
    prior
  } else {
    @boundary.default_state(object._get("kind"), @core.undefined())
  }
  edit(store, [change(base, merge(state, patch))], separate~)
}

///|
pub fn translate(
  store : @core.Any,
  scene_id : String,
  composition_id : String,
  starts : @core.Any,
  dx : Double,
  dy : Double,
) -> Unit {
  let scene = current_scene(store, scene_id)
  let composition = scene._get("compositions")._get(composition_id)
  if !truthy(composition) {
    return
  }
  let changes = []
  for id in @core.object_keys(starts) {
    let object = scene._get("objects")._get(id)
    if !truthy(object) ||
      truthy(object._get("locked")) ||
      !truthy(composition._get("states")._get(id)) {
      continue
    }
    let point = starts._get(id)
    let x = round((number(point._get("x")) + dx) * 10.0) / 10.0
    let y = round((number(point._get("y")) + dy) * 10.0) / 10.0
    changes.append(
      changes_for(
        ["scenes", scene_id, "compositions", composition_id, "states", id],
        record([("x", @core.any(x)), ("y", @core.any(y))]),
      ),
    )
  }
  edit(store, changes, separate=false)
}

///|
pub fn add_object(
  store : @core.Any,
  scene_id : String,
  composition_id : String,
  kind : String,
  patch : @core.Any,
  image : @core.Any,
  image_name : @core.Any,
) -> String {
  let scene = current_scene(store, scene_id)
  let compositions = scene._get("compositions")
  if !truthy(compositions._get(composition_id)) {
    @core.throw_error("追加先の Composition が見つかりません。")
    return ""
  }
  if kind == "image" {
    try @boundary.read_image_asset(image) |> ignore catch {
      error => @core.throw_(native_error(error))
    }
  }
  let objects = scene._get("objects")
  if @core.object_keys(objects).length() >= 500 {
    @core.throw_error(
      "オブジェクトは 500 件まで追加できます。",
    )
    return ""
  }
  let mut count = 1
  let mut order = -1.0
  for id in @core.object_keys(objects) {
    let object = objects._get(id)
    if @core.equal(object._get("kind"), @core.any(kind)) {
      count += 1
    }
    order = order.max(number(object._get("order")))
  }
  let label = match @boundary.read_object_kind(@core.any(kind)) {
    Circle => "Circle"
    Rectangle => "Rectangle"
    Text => "Text"
    Equation => "Equation"
    Path => "Path"
    Arrow => "Arrow"
    NumberLine => "Number line"
    Image => "Image"
    Video => "Video"
  }
  let supplied = if @core.is_nullish(image_name) {
    ""
  } else {
    slice_text(image_name.cast(), 200)
  }
  let name = if supplied.is_empty() {
    label + " " + count.to_string()
  } else {
    supplied
  }
  let id = @boundary.new_id("obj")
  let state = @boundary.default_state(@core.any(kind), patch)
  let object = record([
    ("id", @core.any(id)),
    ("name", @core.any(name)),
    ("kind", @core.any(kind)),
    ("order", @core.any(order + 1.0)),
    ("groupId", @core.null()),
    ("locked", @core.any(false)),
  ])
  if truthy(image) {
    object._set("image", image)
  }
  let changes = [change(["scenes", scene_id, "objects", id], object)]
  for cid in @core.object_keys(compositions) {
    let composition = compositions._get(cid)
    let cid : String = composition._get("id").cast()
    changes.push(
      change(
        ["scenes", scene_id, "compositions", cid, "states", id],
        merge(state, record([("visible", @core.any(cid == composition_id))])),
      ),
    )
  }
  let transitions = scene._get("transitions")
  for tid in @core.object_keys(transitions) {
    let transition = transitions._get(tid)
    let tid : String = transition._get("id").cast()
    changes.push(
      change(
        ["scenes", scene_id, "transitions", tid, "tracks", id],
        @boundary.default_track(
          id,
          record([
            ("duration", transition._get("duration")),
            ("implicit", @core.any(true)),
          ]),
        ),
      ),
    )
  }
  edit(store, changes)
  id
}

///|
pub fn linked_ids(
  store : @core.Any,
  scene_id : String,
  selected : FixedArray[String],
) -> FixedArray[String] {
  @boundary.editable_group_members(current_scene(store, scene_id), selected).map(fn(
      object,
    ) {
      object._get("id").cast()
    },
  )
}

///|
pub fn link(
  store : @core.Any,
  scene_id : String,
  selected : FixedArray[String],
) -> Unit {
  let ids = linked_ids(store, scene_id, selected)
  if ids.length() < 2 {
    return
  }
  let group = @boundary.new_id("group")
  edit(
    store,
    ids
    .iter()
    .map(fn(id) {
      change(["scenes", scene_id, "objects", id, "groupId"], @core.any(group))
    })
    .to_array(),
  )
}

///|
pub fn unlink(
  store : @core.Any,
  scene_id : String,
  selected : FixedArray[String],
) -> Unit {
  edit(
    store,
    linked_ids(store, scene_id, selected)
    .iter()
    .map(fn(id) {
      change(["scenes", scene_id, "objects", id, "groupId"], @core.null())
    })
    .to_array(),
  )
}

///|
pub fn hide(
  store : @core.Any,
  scene_id : String,
  composition_id : String,
  ids : FixedArray[String],
) -> Unit {
  let scene = current_scene(store, scene_id)
  let composition = scene._get("compositions")._get(composition_id)
  let changes = []
  if truthy(composition) {
    for id in ids {
      let object = scene._get("objects")._get(id)
      if truthy(object) &&
        !truthy(object._get("locked")) &&
        truthy(composition._get("states")._get(id)) {
        changes.push(
          change(
            [
              "scenes", scene_id, "compositions", composition_id, "states", id, "visible",
            ],
            @core.any(false),
          ),
        )
      }
    }
  }
  edit(store, changes)
}

///|
pub fn paste(
  store : @core.Any,
  scene_id : String,
  composition_id : String,
  clipboard : @core.Any,
  offset : Double,
) -> @core.Any {
  let result = @boundary.paste_object_changes(
    current_scene(store, scene_id),
    composition_id,
    clipboard,
    @core.any(offset),
  )
  store._call("edit", [result._get("changes")]) |> ignore
  result._get("ids")
}

///|
pub fn duplicate(
  store : @core.Any,
  scene_id : String,
  composition_id : String,
  ids : FixedArray[String],
) -> @core.Any {
  let scene = current_scene(store, scene_id)
  let objects = scene._get("objects")
  let selected = ids
    .iter()
    .filter(fn(id) {
      let object = objects._get(id)
      @core.is_nullish(object) || !truthy(object._get("locked"))
    })
    .to_array()
  let clipboard = @boundary.copy_objects(
    scene,
    composition_id,
    FixedArray::from_array(selected[:]),
  )
  paste(store, scene_id, composition_id, clipboard, 24.0)
}
