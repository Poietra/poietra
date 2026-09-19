///|
pub struct PreparedStructureAppend {
  id : String
  publish : () -> Unit
}

///|
fn creation_error(error : @editor.StructureCreationError) -> String {
  match error {
    SceneLimit => "Scene は 100 件まで追加できます。"
    CompositionLimit => "Composition は 100 件まで追加できます。"
    EmptyPalette => "Composition の色を設定してください。"
  }
}

///|
fn append_parent(
  doc : @core.Any,
  path : FixedArray[String],
  type_ : @core.Any,
  host : @core.Any,
) -> @core.Any {
  let value = get_shared(doc, path, host)
  if !is_instance(value, type_) {
    fail(
      "作成先の共有データが見つかりません。同期完了後にもう一度追加してください。",
    )
  }
  value
}

///|
fn prepared_append(
  id : String,
  order : @core.Any,
  writes : Array[(@core.Any, String, @core.Any)],
  retained : @core.Any,
  host : @core.Any,
) -> PreparedStructureAppend {
  // The caller supplies one captured local transaction. Resolve every parent
  // and encode every detached map before constructing this publication step.
  {
    id,
    publish: fn() {
      if is_instance(retained, host._get("Map")) &&
        strict_equal(map_get(retained, "deleted"), @core.any(true)) {
        map_set(retained, "deleted", @core.any(false))
      }
      for (parent, key, value) in writes {
        map_set(parent, key, value)
      }
      order._call("push", [@core.any(([id] : FixedArray[String]))]) |> ignore
    },
  }
}

///|
pub fn prepare_scene_append(
  doc : @core.Any,
  project : @core.Any,
  host : @core.Any,
) -> PreparedStructureAppend {
  let plan = match
    @editor.plan_scene_append(string_array(project._get("sceneOrder")), new_id) {
    Err(error) => return fail(creation_error(error))
    Ok(plan) => plan
  }
  let scenes = append_parent(doc, ["scenes"], host._get("Map"), host)
  let order = append_parent(doc, ["sceneOrder"], host._get("Array"), host)
  let retained = match plan.retained_id {
    None => @core.undefined()
    Some(id) => map_get(scenes, id)
  }
  let value = to_shared(encode_Scene(plan.value), host)
  prepared_append(
    plan.value.id,
    order,
    [(scenes, plan.value.id, value)],
    retained,
    host,
  )
}

///|
pub fn prepare_composition_append(
  doc : @core.Any,
  scene_id : String,
  scene : @core.Any,
  colors : @core.Any,
  host : @core.Any,
) -> PreparedStructureAppend {
  let ids = string_array(scene._get("compositionOrder"))
  // Preserve the current snapshot's state references; copying every Scene or
  // decoding its object payloads adds no information to the creation plan.
  let last = match ids.last() {
    None => @core.undefined()
    Some(id) => scene._get("compositions")._get(id)
  }
  let plan = match
    @editor.plan_composition_append(
      ids.length(),
      if truthy(last) {
        Some(last._get("id").cast())
      } else {
        None
      },
      @core.object_keys(scene._get("objects")),
      string_array(colors),
      new_id,
    ) {
    Err(error) => return fail(creation_error(error))
    Ok(plan) => plan
  }
  let compositions = append_parent(
    doc,
    ["scenes", scene_id, "compositions"],
    host._get("Map"),
    host,
  )
  let order = append_parent(
    doc,
    ["scenes", scene_id, "compositionOrder"],
    host._get("Array"),
    host,
  )
  let incoming = match plan.incoming {
    None => None
    Some(transition) => {
      let parent = append_parent(
        doc,
        ["scenes", scene_id, "transitions"],
        host._get("Map"),
        host,
      )
      Some(
        (parent, transition.id, to_shared(encode_Transition(transition), host)),
      )
    }
  }
  let value = encode_Composition(plan.value)
  let retained = match plan.source_id {
    None => @core.undefined()
    Some(id) => {
      value._set("states", last._get("states"))
      map_get(compositions, id)
    }
  }
  let writes = [(compositions, plan.value.id, to_shared(value, host))]
  if incoming is Some(write) {
    writes.push(write)
  }
  prepared_append(plan.value.id, order, writes, retained, host)
}
