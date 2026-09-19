///|
pub(all) struct TargetTransition {
  from_id : String
  to_id : String
  object_ids : Array[String]
}

///|
pub(all) struct TargetScene {
  id : String
  objects : Map[String, String]
  compositions : Map[String, String]
  transitions : Map[String, TargetTransition]
}

///|
pub(all) struct TargetWrite {
  path : Array[String]
  name : String?
  transition : TargetTransition?
}

///|
pub(all) struct ProposalTarget {
  selection : ChatSelection
  object_ids : Array[String]
  label : String
  created : Bool
}

///|
pub fn proposal_targets(
  writes : Array[TargetWrite],
  scene : TargetScene,
) -> Array[ProposalTarget] {
  let added_names : Map[String, String] = Map([])
  let compositions = scene.compositions.copy()
  let transitions = scene.transitions.copy()
  let added : Set[String] = Set([])
  for write in writes {
    let path = write.path
    if path.length() != 4 || path[0] != "scenes" || path[1] != scene.id {
      continue
    }
    match path[2] {
      "objects" => if write.name is Some(name) { added_names[path[3]] = name }
      "compositions" =>
        if !compositions.contains(path[3]) && write.name is Some(name) {
          compositions[path[3]] = name
          added.add("composition:" + path[3])
        }
      "transitions" =>
        if !transitions.contains(path[3]) &&
          write.transition is Some(transition) {
          transitions[path[3]] = transition
          added.add("transition:" + path[3])
        }
      _ => ()
    }
  }
  let indices : Map[String, Int] = Map([])
  let result : Array[ProposalTarget] = []
  for write in writes {
    let path = write.path
    if path.length() < 4 || path[0] != "scenes" || path[1] != scene.id {
      continue
    }
    let id = path[3]
    let (kind, selection) = match path[2] {
      "compositions" => ("composition:", Composition(id))
      "transitions" => ("transition:", Transition(id))
      _ => continue
    }
    let key = kind + id
    let index = match indices.get(key) {
      Some(index) => index
      None => {
        let label = match selection {
          Composition(_) =>
            compositions.get(id).unwrap_or("削除された対象")
          Transition(_) =>
            match transitions.get(id) {
              Some(transition) =>
                "Transition · " +
                compositions.get(transition.from_id).unwrap_or("undefined") +
                " → " +
                compositions.get(transition.to_id).unwrap_or("undefined")
              None => "削除された対象"
            }
        }
        let index = result.length()
        result.push({
          selection,
          object_ids: [],
          label,
          created: added.contains(key),
        })
        indices[key] = index
        index
      }
    }
    let target = result[index]
    if path.length() > 5 &&
      (path[4] == "states" || path[4] == "tracks") &&
      !path[5].is_empty() &&
      !target.object_ids.contains(path[5]) {
      target.object_ids.push(path[5])
    }
    if selection is Transition(_) && path.length() == 4 && target.created {
      result[index] = {
        ..target,
        object_ids: transitions
        .get(id)
        .map(fn(t) { t.object_ids.copy() })
        .unwrap_or([]),
      }
    }
  }
  result.map(fn(target) {
    let names : Array[String] = []
    for id in target.object_ids {
      let name = scene.objects
        .get(id)
        .unwrap_or(added_names.get(id).unwrap_or(""))
      if !name.is_empty() {
        names.push(name)
      }
    }
    {
      ..target,
      label: (if target.created { "追加 · " } else { "" }) +
      target.label +
      (if names.is_empty() { "" } else { " · " + names.join(", ") }),
    }
  })
}
