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
  if @core.object_keys(patch).contains("parentId") {
    let changes = @boundary.reparent_changes(
      @boundary.get_value(store._get("doc"), ["scenes", scene], host(store)),
      id,
      patch._get("parentId"),
    )
    for key in @core.object_keys(patch) {
      if key != "parentId" {
        changes.push(
          change(["scenes", scene, "objects", id, key], patch._get(key)),
        )
      }
    }
    edit(store, changes)
  } else {
    edit(store, changes_for(["scenes", scene, "objects", id], patch))
  }
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
    let changes = changes_for(base, patch)
    if @core.object_keys(patch)
      .iter()
      .any(fn(key) {
        ["anchorX", "anchorY", "scaleX", "scaleY", "shear"].contains(key)
      }) {
      changes.push(change(["version"], @core.any(2)))
    }
    edit(store, changes, separate~)
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
  let objects = scene._get("objects")
  let states = composition._get("states")
  let targets : Array[@editor.StateTarget[@scene.Point]] = @core.object_keys(
    starts,
  ).map(fn(id) {
    let object = objects._get(id)
    let point = starts._get(id)
    {
      id,
      locked: if @core.is_nullish(object) {
        None
      } else {
        Some(truthy(object._get("locked")))
      },
      state: if @core.is_nullish(states._get(id)) {
        None
      } else {
        Some({ x: number(point._get("x")), y: number(point._get("y")), })
      },
    }
  })
  let hierarchical = targets.any(fn(t) {
    t.locked == Some(false) &&
    t.state is Some(_) &&
    truthy(objects._get(t.id)._get("parentId"))
  })
  let positions = if hierarchical {
    let moves : Array[@editor.WorldMove] = []
    for target in targets {
      if target.locked == Some(false) && target.state is Some(start) {
        moves.push({ id: target.id, start, delta: { x: dx, y: dy, }, })
      }
    }
    @boundary.project_world_moves(scene, composition_id, moves)
  } else {
    @editor.translated_objects(targets, dx, dy)
  }
  edit(
    store,
    @boundary.object_position_changes(scene_id, composition_id, positions),
    separate=false,
  )
}

///|
fn creation_target(scene : @core.Any) -> @editor.ObjectCreationTarget {
  let objects = scene._get("objects")
  let compositions = scene._get("compositions")
  let transitions = scene._get("transitions")
  {
    objects: @core.object_keys(objects).map(fn(id) {
      let object = objects._get(id)
      (
        @boundary.read_object_kind(object._get("kind")),
        number(object._get("order")),
      )
    }),
    compositions: @core.object_keys(compositions).map(fn(id) {
      compositions._get(id)._get("id").cast()
    }),
    transitions: @core.object_keys(transitions).map(fn(id) {
      let transition = transitions._get(id)
      (transition._get("id").cast(), number(transition._get("duration")))
    }),
  }
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
  // Keep validation/error ordering at the public boundary.
  if !truthy(scene._get("compositions")._get(composition_id)) {
    @core.throw_error("追加先の Composition が見つかりません。")
    return ""
  }
  if kind == "image" {
    try @boundary.read_image_asset(image) |> ignore catch {
      error => @core.throw_(native_error(error))
    }
  }
  let image = if truthy(image) {
    Some(@scene.ImageAsset::{
      src: image._get("src").cast(),
      width: number(image._get("width")),
      height: number(image._get("height")),
    })
  } else {
    None
  }
  let result = @editor.create_object(
    creation_target(scene),
    composition_id,
    @boundary.read_object_kind(@core.any(kind)),
    @boundary.read_object_state(@boundary.default_state(@core.any(kind), patch)),
    image,
    if @core.is_nullish(image_name) {
      None
    } else {
      Some(image_name.cast())
    },
    @boundary.new_id,
  )
  match result {
    Err(error) => {
      @core.throw_error(
        match error {
          MissingComposition =>
            "追加先の Composition が見つかりません。"
          ObjectLimit =>
            "オブジェクトは 500 件まで追加できます。"
        },
      )
      ""
    }
    Ok(addition) => {
      edit(store, @boundary.object_insertion_changes(scene_id, [addition]))
      addition.object.id
    }
  }
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
  let targets : Array[@editor.StateTarget[Unit]] = if @core.is_nullish(
      composition,
    ) {
    []
  } else {
    let objects = scene._get("objects")
    let states = composition._get("states")
    ids
    .iter()
    .map(fn(id) {
      let object = objects._get(id)
      @editor.StateTarget::{
        id,
        locked: if @core.is_nullish(object) {
          None
        } else {
          Some(truthy(object._get("locked")))
        },
        state: if @core.is_nullish(states._get(id)) {
          None
        } else {
          Some(())
        },
      }
    })
    .to_array()
  }
  edit(
    store,
    @editor.editable_state_ids(targets).map(fn(id) {
      change(
        [
          "scenes", scene_id, "compositions", composition_id, "states", id, "visible",
        ],
        @core.any(false),
      )
    }),
  )
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
