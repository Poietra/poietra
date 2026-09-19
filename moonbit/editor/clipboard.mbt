///|
pub(all) struct ObjectClipboard {
  objects : Array[@scene.SceneObject]
  states : Map[String, @scene.ObjectState]
}

///|
pub(all) struct PasteHistory {
  text : String
  scene : String
  composition : String
  count : Int
}

///|
pub fn next_paste(
  previous : PasteHistory?,
  text : String,
  scene : String,
  composition : String,
  in_place : Bool,
) -> (PasteHistory, Double) {
  let count = match previous {
    Some(previous) if previous.text == text &&
      previous.scene == scene &&
      previous.composition == composition => previous.count + 1
    _ => 1
  }
  let count = if in_place { 0 } else { count }
  ({ text, scene, composition, count, }, count.to_double() * 24.0)
}

///|
pub fn copied_object_ids(
  ordered : Array[String],
  present : Array[String],
  ids : Array[String],
) -> Array[String] {
  let selected = Set::from_array(ids)
  let present = Set::from_array(present)
  ordered.filter(fn(id) { selected.contains(id) && present.contains(id) })
}

///|
pub(all) struct PasteScene {
  objects : Array[(String, Double)]
  compositions : Array[String]
  transitions : Array[(String, Double)]
}

///|
pub fn paste_objects(
  scene : PasteScene,
  composition_id : String,
  clipboard : ObjectClipboard,
  offset : Double,
  id : (String) -> String,
) -> Result[Array[ObjectInsertion], String] {
  if !scene.compositions.contains(composition_id) {
    return Err("貼り付け先の Composition が見つかりません。")
  }
  let counts : Map[String, Int] = Map([])
  let groups : Map[String, String] = Map([])
  let names : Set[String] = Set([])
  let mut order = -1.0
  for (name, position) in scene.objects {
    names.add(name)
    order = @scene.maximum(order, position)
  }
  order += 1.0
  for object in clipboard.objects {
    if !clipboard.states.contains(object.id) {
      return Err(
        "コピーしたオブジェクトの状態がありません。",
      )
    }
    if object.groupId is Some(group) && !group.is_empty() {
      counts[group] = counts.get(group).unwrap_or(0) + 1
    }
  }
  let result : Array[ObjectInsertion] = []
  let copied_ids : Map[String, String] = Map([])
  for object in clipboard.objects {
    let original = clipboard.states[object.id]
    let object_id = id("obj")
    copied_ids[object.id] = object_id
    let offset = if object.parentId is Some(_) { 0.0 } else { offset }
    let group = match object.groupId {
      Some(group) =>
        if counts.get(group).unwrap_or(0) > 1 {
          match groups.get(group) {
            Some(value) => Some(value)
            None => {
              let value = id("group")
              groups[group] = value
              Some(value)
            }
          }
        } else {
          None
        }
      None => None
    }
    let mut name = object.name
    for index = 1; names.contains(name); index = index + 1 {
      let suffix = " copy" + (if index > 1 { " \{index}" } else { "" })
      let mut length = (200 - suffix.length()).max(0).min(object.name.length())
      if length > 0 {
        let code = object.name.code_unit_at(length - 1).to_int()
        if code >= 0xd800 && code <= 0xdbff {
          length -= 1
        }
      }
      name = object.name[:length].to_owned() + suffix
    }
    names.add(name)
    let states = []
    for composition in scene.compositions {
      states.push(
        (
          composition,
          {
            ..original,
            x: original.x + offset,
            y: original.y + offset,
            visible: composition == composition_id,
          },
        ),
      )
    }
    let tracks = []
    for (transition, duration) in scene.transitions {
      tracks.push(
        (
          transition,
          { ..@scene.default_track(object_id, duration), implicit: Some(true), },
        ),
      )
    }
    result.push({
      object: {
        ..object,
        id: object_id,
        name,
        groupId: group,
        order,
        locked: false,
      },
      states,
      tracks,
    })
    order += 1.0
  }
  Ok(
    result.map(fn(item) {
      {
        ..item,
        object: {
          ..item.object,
          parentId: item.object.parentId.bind(fn(id) { copied_ids.get(id) }),
        },
      }
    }),
  )
}
