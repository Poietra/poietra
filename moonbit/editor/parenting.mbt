///|
pub(all) struct ReparentPlan {
  parent : String?
  states : Array[(String, @scene.ObjectState)]
}

///|
pub fn plan_reparent(
  scene : @scene.Scene,
  id : String,
  parent : String?,
) -> Result[ReparentPlan, String] {
  guard scene.objects.get(id) is Some(object) else {
    return Err(
      "親子付けするオブジェクトが見つかりません。",
    )
  }
  if object.locked {
    return Err(
      "ロックされたオブジェクトは親子付けできません。",
    )
  }
  if object.parentId == parent {
    return Ok({ parent, states: [], })
  }
  if parent is Some(pid) && !scene.objects.contains(pid) {
    return Err("親オブジェクトが見つかりません。")
  }
  let visited : Set[String] = Set([])
  let mut cursor = parent
  while cursor is Some(pid) {
    if pid == id || visited.contains(pid) {
      return Err("自分自身や子孫を親にはできません。")
    }
    visited.add(pid)
    cursor = match scene.objects.get(pid) {
      Some(object) => object.parentId
      None => None
    }
  }
  let hierarchy = @scene.prepare_hierarchy(scene.objects.values().collect())
  let states = []
  for cid, composition in scene.compositions {
    guard composition.states.get(id) is Some(previous) else { continue }
    let world = hierarchy.matrices(composition.states)
    let parent_matrix = match parent {
      Some(pid) => world.get(pid).unwrap_or(@scene.Affine::identity())
      None => @scene.Affine::identity()
    }
    guard parent_matrix.inverse() is Some(inverse) else {
      return Err(
        "親の拡縮が 0 または極端に小さい Composition があります。拡縮を戻してから親子付けしてください。",
      )
    }
    let next = previous.with_matrix(inverse.compose(world[id]))
    if [
        next.x,
        next.y,
        next.rotation,
        next.scaleX.unwrap(),
        next.scaleY.unwrap(),
        next.shear.unwrap(),
      ].any(fn(n) { n.is_nan() || n.is_inf() || n.abs() > 100000.0 }) {
      return Err(
        "親子付け後の座標が保存可能な範囲を超えます。",
      )
    }
    states.push((cid, next))
  }
  Ok({ parent, states, })
}

///|
/// Moving the anchor changes its coordinate reference, preserving geometry.
pub fn move_anchor(
  state : @scene.ObjectState,
  x : Double,
  y : Double,
) -> @scene.ObjectState {
  let position = state.local_matrix().point({ x, y, })
  { ..state, x: position.x, y: position.y, anchorX: Some(x), anchorY: Some(y), }
}

///|
pub(all) struct WorldMove {
  id : String
  start : @scene.Point
  delta : @scene.Point
}

///|
/// A selected ancestor already contributes its movement. Subtract that once
/// before projecting the remainder into the object's parent coordinates.
pub fn project_world_moves(
  moves : Array[WorldMove],
  parents : Map[String, String],
  inverse_parent : (String) -> @scene.Affine?,
) -> Array[(String, @scene.Point)] {
  let deltas : Map[String, @scene.Point] = Map([])
  for movement in moves {
    deltas[movement.id] = movement.delta
  }
  let result : Array[(String, @scene.Point)] = []
  for movement in moves {
    let mut ancestor = parents.get(movement.id)
    let mut inherited : @scene.Point = { x: 0.0, y: 0.0, }
    while ancestor is Some(id) {
      if deltas.get(id) is Some(delta) {
        inherited = delta
        break
      }
      ancestor = parents.get(id)
    }
    let delta : @scene.Point = {
      x: movement.delta.x - inherited.x,
      y: movement.delta.y - inherited.y,
    }
    if delta.x.abs() < 1.0e-10 && delta.y.abs() < 1.0e-10 {
      continue
    }
    if inverse_parent(movement.id) is Some(inverse) {
      let projected = inverse.vector(delta)
      result.push(
        (
          movement.id,
          {
            x: movement.start.x + projected.x,
            y: movement.start.y + projected.y,
          },
        ),
      )
    }
  }
  result
}
