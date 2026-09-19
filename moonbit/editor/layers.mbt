///|
/// Shift toggles a complete group without duplicating selected IDs.
pub fn select_layer_members(
  selected : Array[String],
  members : Array[String],
  additive : Bool,
) -> Array[String] {
  if !additive {
    return members.copy()
  }
  let targets : Map[String, Bool] = Map([])
  let current : Map[String, Bool] = Map([])
  for id in selected {
    current[id] = true
  }
  for id in members {
    targets[id] = true
  }
  if members.all(fn(id) { current.contains(id) }) {
    selected.filter(fn(id) { !targets.contains(id) })
  } else {
    let next = selected.copy()
    for id in members {
      if !current.contains(id) {
        next.push(id)
        current[id] = true
      }
    }
    next
  }
}
