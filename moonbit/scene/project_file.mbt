///|
pub fn valid_project_references(project : Project) -> Bool {
  let scene_ids : Set[String] = Set([])
  for id in project.sceneOrder {
    if scene_ids.contains(id) ||
      project.scenes.get(id).map(fn(scene) { scene.id != id }).unwrap_or(true) {
      return false
    }
    scene_ids.add(id)
  }
  if scene_ids.length() != project.scenes.length() {
    return false
  }
  for _, scene in project.scenes {
    let ids : Set[String] = Set([])
    for id in scene.compositionOrder {
      if ids.contains(id) ||
        scene.compositions
        .get(id)
        .map(fn(comp) { comp.id != id })
        .unwrap_or(true) {
        return false
      }
      ids.add(id)
    }
    if ids.length() != scene.compositions.length() ||
      scene.objects.length() > 500 ||
      scene.audioTracks
      .map(fn(tracks) { tracks.length() > 100 })
      .unwrap_or(false) {
      return false
    }
    for id, object in scene.objects {
      if (object.kind == Network || object.kind == Surface) &&
        project.version < 6 {
        return false
      }
      if object.kind == Geometry && project.version < 5 {
        return false
      }
      if object.kind == Graph && project.version < 4 {
        return false
      }
      if object.id != id {
        return false
      }
      if object.clipChildren == Some(true) &&
        (object.kind != Rectangle || project.version < 3) {
        return false
      }
    }
    if scene.audioTracks is Some(tracks) {
      for id, track in tracks {
        if track.id != id {
          return false
        }
      }
    }
    for _, comp in scene.compositions {
      for id, state in comp.states {
        if !scene.objects.contains(id) {
          return false
        }
        if (scene.objects[id].kind == Network && state.network is None) ||
          (scene.objects[id].kind == Surface && state.surface is None) {
          return false
        }
        if state.network is Some(value) &&
          (project.version < 6 || network_validation_error(value) is Some(_)) {
          return false
        }
        if state.surface is Some(value) &&
          (project.version < 6 || surface_validation_error(value) is Some(_)) {
          return false
        }
        if scene.objects[id].kind == Graph && state.graph is None {
          return false
        }
        if scene.objects[id].kind == Geometry && state.geometry is None {
          return false
        }
        if state.geometry is Some(geometry) &&
          (
            project.version < 5 ||
            geometry_validation_error(geometry) is Some(_)
          ) {
          return false
        }
        if state.graph is Some(graph) &&
          (project.version < 4 || graph_validation_error(graph) is Some(_)) {
          return false
        }
      }
    }
    let outgoing : Set[String] = Set([])
    for id, transition in scene.transitions {
      guard scene.compositionOrder.search(transition.fromId) is Some(index) else {
        return false
      }
      if transition.id != id ||
        index + 1 >= scene.compositionOrder.length() ||
        scene.compositionOrder[index + 1] != transition.toId ||
        outgoing.contains(transition.fromId) {
        return false
      }
      outgoing.add(transition.fromId)
      for object_id, track in transition.tracks {
        if project.version < 4 &&
          (
            track.graphTiming is Some(_) ||
            track.keyframes
            .map(fn(keys) {
              keys
              .values()
              .any(fn(k) {
                k.property is GraphA ||
                k.property is GraphB ||
                k.property is GraphC
              })
            })
            .unwrap_or(false)
          ) {
          return false
        }
        if !scene.objects.contains(object_id) ||
          track.objectId != object_id ||
          !valid_file_track(track, transition.duration) {
          return false
        }
      }
    }
  }
  true
}

///|
fn valid_file_track(track : Track, limit : Double) -> Bool {
  if track.keyframes is Some(keys) &&
    (keys.length() > 1024 || keys.values().any(fn(k) { !valid_keyframe(k) })) {
    return false
  }
  let start = if track.implicit == Some(true) { 0.0 } else { track.start }
  let duration = if track.implicit == Some(true) {
    limit
  } else {
    track.duration
  }
  if !valid_timing_bounds(start, duration, limit) || !valid_easing(track.easing) {
    return false
  }
  for
    timing in [
      track.positionTiming,
      track.opacityTiming,
      track.sizeTiming,
      track.rotationTiming,
      track.fillTiming,
      track.strokeTiming,
      track.strokeWidthTiming,
      track.fontSizeTiming,
      track.cornerRadiusTiming,
      track.pathTiming,
      track.revealTiming,
      track.graphTiming,
    ] {
    if timing is Some(timing) &&
      (
        !valid_timing_bounds(timing.start, timing.duration, limit) ||
        !valid_easing(timing.easing)
      ) {
      return false
    }
  }
  true
}
