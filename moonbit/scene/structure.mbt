///|
/// Retained CRDT structure is projected without repairing or overwriting it.
/// Payloads are intentionally absent: deleting/reordering must not copy media or
/// states, and each projected transition keeps its original shared identity.
pub(all) struct RetainedComposition {
  deleted : Bool
  incoming : String?
}

///|
pub(all) struct TransitionLink {
  source_key : String
  id : String
  from_id : String
  to_id : String
}

///|
pub(all) struct StructureView {
  order : Array[String]
  links : Array[TransitionLink]
}

///|
pub fn retained_order(
  order : Array[String],
  deleted : Map[String, Bool],
) -> Array[String] {
  let seen : Map[String, Bool] = Map([])
  let visible : Array[String] = []
  let mut first : String? = None
  for id in order {
    guard deleted.get(id) is Some(is_deleted) else { continue }
    if seen.contains(id) {
      continue
    }
    seen[id] = true
    if first is None {
      first = Some(id)
    }
    if !is_deleted {
      visible.push(id)
    }
  }
  if visible.is_empty() && first is Some(id) {
    visible.push(id)
  }
  visible
}

///|
/// JS's deterministic string ordering compares UTF-16 units, not locale or length.
fn compare_ids_utf16(a : String, b : String) -> Int {
  let length = a.length().min(b.length())
  for index = 0; index < length; index = index + 1 {
    let x = a.code_unit_at(index).to_int()
    let y = b.code_unit_at(index).to_int()
    if x != y {
      return if x < y { -1 } else { 1 }
    }
  }
  a.length() - b.length()
}

///|
pub fn structure_view(
  order : Array[String],
  compositions : Map[String, RetainedComposition],
  transitions : Map[String, TransitionLink],
) -> StructureView {
  let deleted = Map([])
  for id, composition in compositions {
    deleted[id] = composition.deleted
  }
  let visible = retained_order(order, deleted)
  let incoming : Map[String, Array[TransitionLink]] = Map([])
  for transition in transitions.values() {
    let candidates = match incoming.get(transition.to_id) {
      Some(candidates) => candidates
      None => {
        let candidates = []
        incoming[transition.to_id] = candidates
        candidates
      }
    }
    candidates.push(transition)
  }
  for candidates in incoming.values() {
    candidates.sort_by(fn(a, b) { compare_ids_utf16(a.id, b.id) })
  }
  let links : Array[TransitionLink] = []
  for index, id in visible {
    if index == 0 {
      continue
    }
    let from_id = visible[index - 1]
    let preferred = compositions[id].incoming.bind(fn(id) {
      transitions.get(id)
    })
    let selected = match preferred {
      Some(value) if value.to_id == id => Some(value)
      _ => {
        let candidates = incoming.get(id).unwrap_or([])
        match
          candidates.iter().find_first(fn(value) { value.from_id == from_id }) {
          Some(value) => Some(value)
          None => candidates.get(0)
        }
      }
    }
    if selected is Some(value) {
      links.push({ ..value, from_id, to_id: id, })
    }
  }
  { order: visible, links, }
}
