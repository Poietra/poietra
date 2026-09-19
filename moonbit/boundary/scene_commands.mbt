///|
priv struct SharedScene {
  scene : @core.Any
  scenes : @core.Any
  order : @core.Any
  shared : @core.Any
  ids : Array[String]
  index : Int
  raw_index : Int
}

///|
extern "js" fn array_insert(
  array : @core.Any,
  index : Int,
  values : FixedArray[String],
) -> Unit =
  #|(array, index, values) => { array.insert(index, values); }

///|
extern "js" fn array_delete(
  array : @core.Any,
  index : Int,
  count : Int,
) -> Unit =
  #|(array, index, count) => { array.delete(index, count); }

///|
fn string_array(value : @core.Any) -> Array[String] {
  decode_array(value, fn(v) { v.cast() })
}

///|
fn shared_strings(value : @core.Any) -> Array[String] {
  string_array(@core.any(shared_array(value)))
}

///|
fn[T] fail(message : String) -> T {
  @core.throw_error(message)
  panic()
}

///|
fn current_scene(doc : @core.Any, id : String, host : @core.Any) -> SharedScene {
  let project = read_project(doc, host)
  let scenes = get_shared(doc, ["scenes"], host)
  let order = get_shared(doc, ["sceneOrder"], host)
  if @core.is_nullish(project) ||
    !is_instance(scenes, host._get("Map")) ||
    !is_instance(order, host._get("Array")) {
    return fail("この Scene はもう存在しません。")
  }
  let shared = map_get(scenes, id)
  let scene = project._get("scenes")._get(id)
  if !truthy(scene) || !is_instance(shared, host._get("Map")) {
    return fail("この Scene はもう存在しません。")
  }
  let ids = string_array(project._get("sceneOrder"))
  {
    scene,
    scenes,
    order,
    shared,
    ids,
    index: @editor.index_of(ids, id),
    raw_index: @editor.index_of(shared_strings(order), id),
  }
}

///|
pub fn rename_scene(
  doc : @core.Any,
  id : String,
  name : String,
  host : @core.Any,
) -> Unit {
  guard @editor.edited_name(name) is Some(value) else {
    return fail("Scene の名前を入力してください。")
  }
  transact(
    doc,
    fn() {
      let current = current_scene(doc, id, host)
      if !strict_equal(current.scene._get("name"), @core.any(value)) {
        map_set(current.shared, "name", @core.any(value))
      }
    },
    @core.any("poietra-local"),
  )
}

///|
pub fn duplicate_scene(
  doc : @core.Any,
  id : String,
  host : @core.Any,
) -> String {
  let mut created = ""
  transact(
    doc,
    fn() {
      let current = current_scene(doc, id, host)
      if current.ids.length() >= 100 {
        fail("Scene は 100 件まで追加できます。")
      }
      let copy = @editor.copy_scene(decode_Scene(current.scene), new_id)
      let value = to_shared(encode_Scene(copy), host)
      if strict_equal(map_get(current.shared, "deleted"), @core.any(true)) {
        map_set(current.shared, "deleted", @core.any(false))
      }
      map_set(current.scenes, copy.id, value)
      array_insert(current.order, current.raw_index + 1, [copy.id])
      created = copy.id
    },
    @core.any("poietra-local"),
  )
  created
}

///|
extern "js" fn selected_value(id : String) -> @core.Any =
  #|selectedId => ({selectedId})

///|
pub fn delete_scene(
  doc : @core.Any,
  id : String,
  host : @core.Any,
) -> @core.Any {
  let mut selected = ""
  transact(
    doc,
    fn() {
      let current = current_scene(doc, id, host)
      if current.ids.length() <= 1 {
        fail("最後の Scene は削除できません。")
      }
      selected = @editor.selection_after_delete(current.ids, current.index).unwrap()
      map_set(current.shared, "deleted", @core.any(true))
    },
    @core.any("poietra-local"),
  )
  selected_value(selected)
}

///|
pub fn move_scene(
  doc : @core.Any,
  id : String,
  direction : Int,
  host : @core.Any,
) -> Unit {
  transact(
    doc,
    fn() {
      let current = current_scene(doc, id, host)
      guard current.ids.get(current.index + direction) is Some(neighbor) else {
        return
      }
      let raw = shared_strings(current.order)
      for index = raw.length() - 1; index >= 0; index = index - 1 {
        if raw[index] == id {
          array_delete(current.order, index, 1)
        }
      }
      let raw = shared_strings(current.order)
      let mut position = @editor.index_of(raw, neighbor)
      if position < 0 {
        position = raw.length()
        array_insert(current.order, position, [neighbor])
      }
      array_insert(
        current.order,
        position + (if direction > 0 { 1 } else { 0 }),
        [id],
      )
    },
    @core.any("poietra-local"),
  )
}

///|
priv struct SharedStructure {
  compositions : @core.Any
  composition : @core.Any
  order : @core.Any
  transitions : @core.Any
  view : @core.Any
  ids : Array[String]
  index : Int
  raw_index : Int
}

///|
fn current_structure(
  doc : @core.Any,
  scene_id : String,
  composition_id : String,
  host : @core.Any,
) -> SharedStructure {
  let compositions = get_shared(doc, ["scenes", scene_id, "compositions"], host)
  let order = get_shared(doc, ["scenes", scene_id, "compositionOrder"], host)
  let transitions = get_shared(doc, ["scenes", scene_id, "transitions"], host)
  if !is_instance(compositions, host._get("Map")) ||
    !is_instance(order, host._get("Array")) ||
    !is_instance(transitions, host._get("Map")) {
    return fail("このシーンはもう存在しません。")
  }
  let composition = map_get(compositions, composition_id)
  let project = read_project(doc, host)
  let view = if @core.is_nullish(project) {
    @core.undefined()
  } else {
    project._get("scenes")._get(scene_id)
  }
  let ids = if @core.is_nullish(view) {
    []
  } else {
    string_array(view._get("compositionOrder"))
  }
  let index = @editor.index_of(ids, composition_id)
  if !is_instance(composition, host._get("Map")) || index < 0 {
    return fail("この Composition はもう存在しません。")
  }
  {
    compositions,
    composition,
    order,
    transitions,
    view,
    ids,
    index,
    raw_index: @editor.index_of(shared_strings(order), composition_id),
  }
}

///|
fn transition_links(scene : @core.Any) -> Array[@scene.TransitionLink] {
  let values = scene._get("transitions")
  @core.object_keys(values).map(fn(key) {
    let value = values._get(key)
    {
      source_key: key,
      id: value._get("id").cast(),
      from_id: value._get("fromId").cast(),
      to_id: value._get("toId").cast(),
    }
  })
}

///|
pub fn duplicate_composition(
  doc : @core.Any,
  scene_id : String,
  composition_id : String,
  host : @core.Any,
) -> String {
  let mut created = ""
  transact(
    doc,
    fn() {
      let current = current_structure(doc, scene_id, composition_id, host)
      let plan = @editor.copy_composition(
        decode_Composition(shared_json(current.composition)),
        current.ids.get(current.index + 1),
        transition_links(current.view),
        @core.object_keys(current.view._get("objects")),
        new_id,
      )
      let outgoing = match plan.outgoing_id {
        Some(id) => map_get(current.transitions, id)
        None => @core.undefined()
      }
      // Complete both encodings before a write: the underlying transaction cannot roll back.
      let copy = to_shared(encode_Composition(plan.copy), host)
      let incoming = to_shared(encode_Transition(plan.incoming), host)
      if strict_equal(map_get(current.composition, "deleted"), @core.any(true)) {
        map_set(current.composition, "deleted", @core.any(false))
      }
      map_set(current.compositions, plan.copy.id, copy)
      array_insert(current.order, current.raw_index + 1, [plan.copy.id])
      if is_instance(outgoing, host._get("Map")) {
        map_set(outgoing, "fromId", @core.any(plan.copy.id))
      }
      map_set(current.transitions, plan.incoming.id, incoming)
      created = plan.copy.id
    },
    @core.any("poietra-local"),
  )
  created
}

///|
extern "js" fn composition_removal(
  selected : String,
  removed : FixedArray[String],
) -> @core.Any =
  #|(selectedId, removedTransitionIds) => ({selectedId, removedTransitionIds})

///|
pub fn delete_composition(
  doc : @core.Any,
  scene_id : String,
  composition_id : String,
  host : @core.Any,
) -> @core.Any {
  let mut result = @core.undefined()
  transact(
    doc,
    fn() {
      let current = current_structure(doc, scene_id, composition_id, host)
      if current.ids.length() <= 1 {
        fail("最後の Composition は削除できません。")
      }
      let plan = @editor.remove_composition(
        composition_id,
        current.ids.get(current.index - 1),
        current.ids.get(current.index + 1),
        transition_links(current.view),
        @core.object_keys(current.view._get("objects")),
        new_id,
      ).unwrap()
      let prepared = match plan.bridge {
        None => None
        Some(bridge) => {
          let next = map_get(current.compositions, bridge.toId)
          if !is_instance(next, host._get("Map")) {
            fail("この Composition はもう存在しません。")
          }
          Some((bridge, to_shared(encode_Transition(bridge), host), next))
        }
      }
      map_set(current.composition, "deleted", @core.any(true))
      if prepared is Some((bridge, value, next)) {
        map_set(current.transitions, bridge.id, value)
        map_set(next, "incomingTransitionId", @core.any(bridge.id))
      }
      result = composition_removal(
        plan.selected_id,
        FixedArray::makei(plan.removed_transition_ids.length(), fn(i) {
          plan.removed_transition_ids[i]
        }),
      )
    },
    @core.any("poietra-local"),
  )
  result
}
