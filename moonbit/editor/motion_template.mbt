///|
pub(all) enum MotionParameter {
  MotionText(String)
  MotionColor(String)
} derive(Eq)

///|
pub(all) struct MotionInsertion {
  objects : Array[ObjectInsertion]
  compositions : Array[@scene.Composition]
  transitions : Array[@scene.Transition]
  source_id : String
}

///|
/// A portable single-Scene motion uses the ordinary project schema. Ancestors
/// remain as hidden transform/clip dependencies so paths and keys need no rebase.
pub fn capture_motion(
  scene : @scene.Scene,
  selection : Array[String],
  name : String,
) -> Result[@scene.Scene, String] {
  let visible = Set::from_array(
    selection.filter(fn(id) { scene.objects.contains(id) }),
  )
  if visible.is_empty() {
    return Err("保存するオブジェクトを選択してください。")
  }
  // Selecting a parent includes its subtree; grouping remains independent.
  let mut changed = true
  while changed {
    changed = false
    for id, object in scene.objects {
      if !visible.contains(id) &&
        object.parentId.map(fn(p) { visible.contains(p) }).unwrap_or(false) {
        visible.add(id)
        changed = true
      }
    }
  }
  let included = Set::from_array(visible.to_array())
  for id in visible.to_array() {
    let mut parent = scene.objects[id].parentId
    while parent is Some(id) && !included.contains(id) {
      guard scene.objects.get(id) is Some(object) else { break }
      included.add(id)
      parent = object.parentId
    }
  }
  let objects : Map[String, @scene.SceneObject] = Map([])
  for id, object in scene.objects {
    if included.contains(id) {
      objects[id] = { ..object, locked: false, }
    }
  }
  let compositions : Map[String, @scene.Composition] = Map([])
  for id in scene.compositionOrder {
    let source = scene.compositions[id]
    let states : Map[String, @scene.ObjectState] = Map([])
    for id, state in source.states {
      if included.contains(id) {
        states[id] = if visible.contains(id) {
          state
        } else {
          { ..state, visible: false, }
        }
      }
    }
    compositions[id] = {
      ..source,
      states,
      deleted: None,
      incomingTransitionId: None,
    }
  }
  let transitions : Map[String, @scene.Transition] = Map([])
  for id, source in scene.transitions {
    let tracks : Map[String, @scene.Track] = Map([])
    for id, track in source.tracks {
      if included.contains(id) {
        tracks[id] = track
      }
    }
    transitions[id] = { ..source, tracks, }
  }
  Ok({
    ..scene,
    name: edited_name(name).unwrap_or("Reusable motion"),
    objects,
    compositions,
    transitions,
    audioTracks: Some(Map([])),
    deleted: None,
  })
}

///|
/// Parameter substitution matches authored values, including intermediate color
/// keys. Repeated text/colors are one input; unrelated authored values stay intact.
pub fn motion_parameters(scene : @scene.Scene) -> Array[MotionParameter] {
  let texts : Set[String] = Set([])
  let colors : Set[String] = Set([])
  for cid in scene.compositionOrder {
    for id, state in scene.compositions[cid].states {
      if scene.objects.get(id) is Some(object) &&
        (object.kind == Text || object.kind == Equation) {
        texts.add(state.text)
      }
      colors.add(state.fill)
      colors.add(state.stroke)
    }
  }
  for _, transition in scene.transitions {
    for _, track in transition.tracks {
      for _, key in track.keyframes.unwrap_or(Map([])) {
        if key.deleted != Some(true) && key.value is CurveColor(color) {
          colors.add(color)
        }
      }
    }
  }
  let text_values = texts.to_array()
  let color_values = colors.to_array()
  text_values.sort()
  color_values.sort()
  text_values.map(fn(value) { MotionText(value) }) +
  color_values.map(fn(value) { MotionColor(value) })
}

///|
pub fn replace_motion(
  scene : @scene.Scene,
  texts : Map[String, String],
  colors : Map[String, String],
) -> @scene.Scene {
  let compositions = scene.compositions.map(fn(_, composition) {
    {
      ..composition,
      states: composition.states.map(fn(id, state) {
        let text = scene.objects
          .get(id)
          .map(fn(o) { o.kind == Text || o.kind == Equation })
          .unwrap_or(false)
        {
          ..state,
          text: if text {
            texts.get(state.text).unwrap_or(state.text)
          } else {
            state.text
          },
          fill: colors.get(state.fill).unwrap_or(state.fill),
          stroke: colors.get(state.stroke).unwrap_or(state.stroke),
        }
      }),
    }
  })
  let transitions = scene.transitions.map(fn(_, transition) {
    {
      ..transition,
      tracks: transition.tracks.map(fn(_, track) {
        {
          ..track,
          keyframes: track.keyframes.map(fn(keys) {
            keys.map(fn(_, key) {
              match key.value {
                CurveColor(color) =>
                  {
                    ..key,
                    value: CurveColor(colors.get(color).unwrap_or(color)),
                  }
                _ => key
              }
            })
          }),
        }
      }),
    }
  })
  { ..scene, compositions, transitions, }
}

///|
/// Check before asset I/O, then again against the latest target on publication.
pub fn validate_motion_insertion(
  target : @scene.Scene,
  source : @scene.Scene,
) -> Result[Unit, String] {
  if source.objects.is_empty() || source.compositionOrder.is_empty() {
    return Err("動きのオブジェクトと場面がありません。")
  }
  if target.objects.length() + source.objects.length() > 500 {
    return Err("1 Scene のオブジェクトは 500 件までです。")
  }
  if target.compositionOrder.length() + source.compositionOrder.length() > 100 {
    return Err("1 Scene の Composition は 100 件までです。")
  }
  if source.audioTracks.map(fn(t) { !t.is_empty() }).unwrap_or(false) {
    return Err(
      "動きの再利用ファイルには独立した音声トラックを含められません。",
    )
  }
  guard target.compositionOrder.last() is Some(last_id) &&
    target.compositions.contains(last_id) else {
    return Err("挿入先の場面が見つかりません。")
  }
  let mut order = 0.0
  for _, object in target.objects {
    order = order.max(object.order + 1.0)
  }
  if order + source.objects.length().to_double() - 1.0 > 100000.0 {
    return Err(
      "レイヤーの重なり順が保存できる範囲を超えます。",
    )
  }
  let prefix = @scene.scene_segments(target)
    .last()
    .map(fn(s) { s.start + s.duration })
    .unwrap_or(0.0)
  if source.objects
    .values()
    .any(fn(o) {
      o.playback.map(fn(p) { p.start + prefix > 86400000.0 }).unwrap_or(false)
    }) {
    return Err(
      "動画の開始時刻が保存できる範囲を超えます。",
    )
  }
  Ok(())
}

///|
/// Append independent poses and tracks. Existing compositions/transitions receive
/// only the new object IDs; their authored values are never rewritten.
pub fn insert_motion(
  target : @scene.Scene,
  source : @scene.Scene,
  allocate : (String) -> String,
) -> Result[MotionInsertion, String] {
  match validate_motion_insertion(target, source) {
    Err(message) => return Err(message)
    Ok(_) => ()
  }
  let last_id = target.compositionOrder.last().unwrap()
  let last = target.compositions[last_id]
  let copy = copy_scene(source, allocate)
  let mut order = 0.0
  let names : Set[String] = Set([])
  for _, object in target.objects {
    order = order.max(object.order + 1.0)
    names.add(object.name)
  }
  let prefix = @scene.scene_segments(target)
    .last()
    .map(fn(s) { s.start + s.duration })
    .unwrap_or(0.0)
  let objects = []
  let ordered = copy.objects.values().to_array()
  ordered.sort_by(fn(a, b) {
    if a.order < b.order {
      -1
    } else if a.order > b.order {
      1
    } else {
      a.id.compare(b.id)
    }
  })
  for item in ordered {
    let mut name = item.name
    for index = 1; names.contains(name); index = index + 1 {
      name = item.name[:item.name.length().min(180)].to_owned() +
        " motion \{index}"
    }
    names.add(name)
    let initial = copy.compositions[copy.compositionOrder[0]].states
      .get(item.id)
      .unwrap_or(@scene.default_state(item.kind))
    objects.push(ObjectInsertion::{
      object: {
        ..item,
        name,
        order,
        locked: false,
        playback: item.playback.map(fn(p) { { ..p, start: p.start + prefix, } }),
      },
      states: target.compositions
      .keys()
      .to_array()
      .map(fn(cid) { (cid, { ..initial, visible: false, }) }),
      tracks: target.transitions
      .values()
      .to_array()
      .map(fn(t) { (t.id, @scene.default_track(item.id, t.duration)) }),
    })
    order += 1.0
  }
  let compositions = []
  for cid in copy.compositionOrder {
    let comp = copy.compositions[cid]
    let states = last.states.copy()
    for id, state in comp.states {
      states[id] = state
    }
    compositions.push({ ..comp, states, })
  }
  let transitions = copy.transitions.values().to_array()
  let bridge = @scene.implicit_transition(
    allocate("transition"),
    last_id,
    copy.compositionOrder[0],
    0.0,
    [],
  )
  transitions.push(bridge)
  // New shared transitions must already contain every object's automatic track
  // and keyframe container. Otherwise server initialization is received as a
  // peer edit and selective Undo correctly retains the apparently shared batch.
  let all_ids = target.objects.keys().to_array() +
    copy.objects.keys().to_array()
  for index, transition in transitions {
    let tracks : Map[String, @scene.Track] = Map([])
    for id in all_ids {
      tracks[id] = match transition.tracks.get(id) {
        Some(track) =>
          { ..track, keyframes: Some(track.keyframes.unwrap_or(Map([]))), }
        None =>
          {
            ..@scene.default_track(id, transition.duration),
            implicit: Some(true),
          }
      }
    }
    transitions[index] = { ..transition, tracks, }
  }
  Ok({ objects, compositions, transitions, source_id: last_id, })
}
