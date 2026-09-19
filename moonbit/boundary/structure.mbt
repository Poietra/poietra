///|
extern "js" fn copy_composition(value : @core.Any) -> @core.Any =
  #|value => { const {deleted, incomingTransitionId, ...rest} = value; return rest; }

///|
extern "js" fn copy_link(
  value : @core.Any,
  from : String,
  to : String,
) -> @core.Any =
  #|(value, fromId, toId) => ({...value, fromId, toId})

///|
extern "js" fn copy_scene(
  value : @core.Any,
  order : FixedArray[String],
  compositions : @core.Any,
  transitions : @core.Any,
  strip_deleted : Bool,
) -> @core.Any =
  #|(value, compositionOrder, compositions, transitions, strip) => { const result = {...value, compositionOrder, compositions, transitions}; if (strip) delete result.deleted; return result; }

///|
extern "js" fn copy_project(
  value : @core.Any,
  order : FixedArray[String],
  scenes : @core.Any,
) -> @core.Any =
  #|(value, sceneOrder, scenes) => ({...value, sceneOrder, scenes})

///|
fn scene_view(input : @core.Any, strip_deleted : Bool) -> @core.Any {
  let compositions = input._get("compositions")
  let transitions = input._get("transitions")
  let retained : Map[String, @scene.RetainedComposition] = Map([])
  for id in @core.object_keys(compositions) {
    let value = compositions._get(id)
    if !@core.is_nullish(value) {
      retained[id] = {
        deleted: truthy(value._get("deleted")),
        incoming: optional(value._get("incomingTransitionId"), fn(v) {
          v.cast()
        }),
      }
    }
  }
  let links : Map[String, @scene.TransitionLink] = Map([])
  for key in @core.object_keys(transitions) {
    let value = transitions._get(key)
    links[key] = {
      source_key: key,
      id: value._get("id").cast(),
      from_id: value._get("fromId").cast(),
      to_id: value._get("toId").cast(),
    }
  }
  let view = @scene.structure_view(
    decode_array(input._get("compositionOrder"), fn(v) { v.cast() }),
    retained,
    links,
  )
  let projected_compositions = @core.new_object()
  for id in view.order {
    projected_compositions._set(id, copy_composition(compositions._get(id)))
  }
  let projected_transitions = @core.new_object()
  for link in view.links {
    projected_transitions._set(
      link.id,
      copy_link(transitions._get(link.source_key), link.from_id, link.to_id),
    )
  }
  copy_scene(
    input,
    FixedArray::makei(view.order.length(), fn(i) { view.order[i] }),
    projected_compositions,
    projected_transitions,
    strip_deleted,
  )
}

///|
extern "js" fn truthy(value : @core.Any) -> Bool = "Boolean"

///|
pub fn scene_structure_view(input : @core.Any) -> @core.Any {
  scene_view(input, false)
}

///|
fn project_view(
  input : @core.Any,
  project_scene : (@core.Any) -> @core.Any,
) -> @core.Any {
  let scenes = input._get("scenes")
  let deleted : Map[String, Bool] = Map([])
  for id in @core.object_keys(scenes) {
    let value = scenes._get(id)
    if !@core.is_nullish(value) {
      deleted[id] = truthy(value._get("deleted"))
    }
  }
  let order = @scene.retained_order(
    decode_array(input._get("sceneOrder"), fn(v) { v.cast() }),
    deleted,
  )
  let projected = @core.new_object()
  for id in order {
    projected._set(id, project_scene(scenes._get(id)))
  }
  copy_project(
    input,
    FixedArray::makei(order.length(), fn(i) { order[i] }),
    projected,
  )
}

///|
pub fn project_structure_view(input : @core.Any) -> @core.Any {
  project_view(input, fn(scene) { scene_view(scene, true) })
}
