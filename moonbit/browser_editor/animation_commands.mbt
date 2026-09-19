///|
pub fn set_transition_duration(
  store : @core.Any,
  scene_id : String,
  id : String,
  requested : Double,
) -> Unit {
  let scene = current_scene(store, scene_id)
  let transition = scene._get("transitions")._get(id)
  if !truthy(transition) {
    return
  }
  if requested.is_nan() ||
    requested.is_inf() ||
    requested < 0.0 ||
    requested > 120000.0 {
    @core.throw_error(
      "Transition の長さは 0〜120000 ms にしてください。",
    )
    return
  }
  let entries = transition._get("tracks")
  let objects = scene._get("objects")
  let tracks = @core.object_keys(entries).map(fn(id) {
    (id, @boundary.read_track(entries._get(id)))
  })
  let locked = fn(id : String) {
    let object = objects._get(id)
    !@core.is_nullish(object) && truthy(object._get("locked"))
  }
  let mut duration = requested
  for (_, track) in tracks {
    if locked(track.objectId) {
      duration = duration.max(
        @scene.track_timing_end(track, track.implicit != Some(true)),
      )
    }
  }
  let base = ["scenes", scene_id, "transitions", id]
  let changes = [change(base + ["duration"], @core.any(duration))]
  for (id, track) in tracks {
    if locked(id) {
      continue
    }
    let path = base + ["tracks", id]
    if track.implicit != Some(true) {
      changes.append(
        changes_for(
          path,
          record([
            ("start", @core.any(track.start.min(duration))),
            (
              "duration",
              @core.any(track.duration.min((duration - track.start).max(0.0))),
            ),
          ]),
        ),
      )
    }
    for channel in channels() {
      if @scene.timing_override(track, channel) is Some(timing) &&
        timing.start + timing.duration > duration {
        let bounded = {
          ..timing,
          start: timing.start.min(duration),
          duration: timing.duration.min((duration - timing.start).max(0.0)),
        }
        changes.push(
          change(path + [channel_key(channel)], @boundary.write_timing(bounded)),
        )
      }
    }
  }
  edit(store, changes)
}

///|
fn editable_transition(
  store : @core.Any,
  scene_id : String,
  transition_id : String,
  object_id : String,
) -> @core.Any? {
  let scene = current_scene(store, scene_id)
  let transition = scene._get("transitions")._get(transition_id)
  let object = scene._get("objects")._get(object_id)
  if !truthy(transition) || !truthy(object) || truthy(object._get("locked")) {
    None
  } else {
    Some(transition)
  }
}

///|
fn skip_equal_easing(
  changes : Array[@core.Any],
  previous : @core.Any,
  next : @core.Any,
) -> Array[@core.Any] {
  changes.filter(fn(change) {
    let path : FixedArray[String] = change._get("path").cast()
    path[path.length() - 1] != "easing" ||
    !@boundary.easings_equal(previous, next)
  })
}

///|
pub fn set_track(
  store : @core.Any,
  scene_id : String,
  transition_id : String,
  object_id : String,
  patch : @core.Any,
  separate : Bool,
) -> Unit {
  guard editable_transition(store, scene_id, transition_id, object_id)
    is Some(transition) else {
    return
  }
  let previous = transition._get("tracks")._get(object_id)
  let limit = number(transition._get("duration"))
  let resolved = @boundary.resolve_track(previous, object_id, limit)
  let track = merge(
    merge(resolved, patch),
    record([("implicit", @core.any(false))]),
  )
  @boundary.validate_animation_track(track, limit)
  let base = [
    "scenes", scene_id, "transitions", transition_id, "tracks", object_id,
  ]
  if !truthy(previous) {
    edit(store, [change(base, track)], separate~)
  } else {
    let promoted = if truthy(previous._get("implicit")) {
      record([
        ("start", resolved._get("start")),
        ("duration", resolved._get("duration")),
        ("implicit", @core.any(false)),
      ])
    } else {
      @core.new_object()
    }
    edit(
      store,
      skip_equal_easing(
        changes_for(base, merge(promoted, patch)),
        previous._get("easing"),
        patch._get("easing"),
      ),
      separate~,
    )
  }
}

///|
pub fn set_property_timing(
  store : @core.Any,
  scene_id : String,
  transition_id : String,
  object_id : String,
  channel : String,
  timing : @core.Any,
  separate : Bool,
) -> Unit {
  guard editable_transition(store, scene_id, transition_id, object_id)
    is Some(transition) else {
    return
  }
  let channel = match @scene.property_channel(channel) {
    Some(channel) => channel
    None => {
      @core.throw_error(
        "アニメーションのプロパティを選択してください。",
      )
      return
    }
  }
  if truthy(timing) {
    @boundary.validate_animation_timing(
      timing,
      number(transition._get("duration")),
    )
  }
  let track = transition._get("tracks")._get(object_id)
  if !truthy(track) {
    @core.throw_error(
      "アニメーションを準備しています。同期完了後にもう一度編集してください。",
    )
    return
  }
  let key = channel_key(channel)
  let current = track._get(key)
  if (!truthy(current) && !truthy(timing)) ||
    (
      truthy(current) &&
      truthy(timing) &&
      @core.equal(current._get("start"), timing._get("start")) &&
      @core.equal(current._get("duration"), timing._get("duration")) &&
      @boundary.easings_equal(current._get("easing"), timing._get("easing"))
    ) {
    return
  }
  let path = [
    "scenes", scene_id, "transitions", transition_id, "tracks", object_id, key,
  ]
  let changes = if truthy(current) && truthy(timing) {
    skip_equal_easing(
      changes_for(path, timing),
      current._get("easing"),
      timing._get("easing"),
    )
  } else {
    [change(path, timing)]
  }
  edit(store, changes, separate~)
}
