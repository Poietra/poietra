///|
pub fn reparent_changes(
  scene : @core.Any,
  id : String,
  parent : @core.Any,
) -> Array[@core.Any] {
  let plan = @editor.plan_reparent(
    decode_Scene(scene),
    id,
    optional(parent, fn(v) { v.cast() }),
  )
  match plan {
    Err(error) => {
      @core.throw_error(error)
      []
    }
    Ok(plan) => {
      if optional(scene._get("objects")._get(id)._get("parentId"), fn(v) {
          v.cast()
        }) ==
        plan.parent {
        return []
      }
      let sid : String = scene._get("id").cast()
      let changes = [
        make_change(
          ["scenes", sid, "objects", id, "parentId"],
          @core.from_option(plan.parent),
        ),
      ]
      for (cid, next) in plan.states {
        let before = scene
          ._get("compositions")
          ._get(cid)
          ._get("states")
          ._get(id)
        let after = encode_ObjectState(next)
        for field in ["x", "y", "rotation", "scaleX", "scaleY", "shear"] {
          if !same_value(before._get(field), after._get(field)) {
            changes.push(
              make_change(
                ["scenes", sid, "compositions", cid, "states", id, field],
                after._get(field),
              ),
            )
          }
        }
      }
      changes.push(make_change(["version"], @core.any(2)))
      changes
    }
  }
}

///|
pub fn read_affine(value : @core.Any) -> @scene.Affine {
  decode_Affine(value)
}

///|
priv struct CompositionMatrices {
  objects : @core.Any
  hierarchy : @scene.Hierarchy
  world : Map[String, @scene.Affine]
}

///|
let composition_transforms : WeakCache[CompositionMatrices] = WeakCache::new()

///|
fn composition_matrices(
  scene : @core.Any,
  composition_id : String,
) -> CompositionMatrices {
  let composition = scene._get("compositions")._get(composition_id)
  let objects = scene._get("objects")
  if composition_transforms.has(composition) {
    let cached = composition_transforms.get(composition)
    if same_value(cached.objects, objects) {
      return cached
    }
  }
  let hierarchy = @scene.prepare_hierarchy(
    decode_map(objects, decode_SceneObject).values().collect(),
  )
  let result = {
    objects,
    hierarchy,
    world: hierarchy.matrices(
      decode_map(composition._get("states"), decode_ObjectState),
    ),
  }
  composition_transforms.set(composition, result)
  result
}

///|
pub fn parent_matrix(
  scene : @core.Any,
  composition_id : String,
  id : String,
) -> @scene.Affine {
  let object = scene._get("objects")._get(id)
  if @core.is_nullish(object._get("parentId")) {
    return @scene.Affine::identity()
  }
  let matrices = composition_matrices(scene, composition_id)
  match matrices.hierarchy.parents.get(id) {
    Some(parent) =>
      matrices.world.get(parent).unwrap_or(@scene.Affine::identity())
    None => @scene.Affine::identity()
  }
}

///|
pub fn object_matrix(
  scene : @core.Any,
  composition_id : String,
  id : String,
) -> @scene.Affine {
  composition_matrices(scene, composition_id).world
  .get(id)
  .unwrap_or(@scene.Affine::identity())
}

///|
pub fn keyframe_curve(
  scene : @core.Any,
  transition : @core.Any,
  id : String,
  property : @scene.CurveProperty,
) -> @scene.PreparedCurve? {
  let a = scene
    ._get("compositions")
    ._get(transition._get("fromId").cast())
    ._get("states")
    ._get(id)
  let b = scene
    ._get("compositions")
    ._get(transition._get("toId").cast())
    ._get("states")
    ._get(id)
  if @core.is_nullish(a) && @core.is_nullish(b) {
    return None
  }
  let from = decode_ObjectState(if @core.is_nullish(a) { b } else { a })
  let to = decode_ObjectState(if @core.is_nullish(b) { a } else { b })
  let track = @scene.resolve_track(
    optional(transition._get("tracks")._get(id), decode_Track),
    id,
    transition._get("duration").cast(),
  )
  @scene.prepare_object_curves(
    track,
    from,
    to,
    !@core.is_nullish(a) && truthy(a._get("visible")),
    !@core.is_nullish(b) && truthy(b._get("visible")),
  )
  .iter()
  .find_first(fn(curve) { curve.property == property })
}

///|
pub fn project_world_moves(
  scene : @core.Any,
  cid : String,
  moves : Array[@editor.WorldMove],
) -> Array[(String, @scene.Point)] {
  let matrices = composition_matrices(scene, cid)
  @editor.project_world_moves(moves, matrices.hierarchy.parents, fn(id) {
    parent_matrix(scene, cid, id).inverse()
  })
}
