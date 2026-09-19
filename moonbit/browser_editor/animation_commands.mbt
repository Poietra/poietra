///|
fn timing_range(value : @core.Any) -> @editor.TimingRange {
  {
    start: number(value._get("start")),
    duration: number(value._get("duration")),
  }
}

///|
fn transition_timings(entries : @core.Any) -> Array[@editor.TrackTimingInput] {
  let channels = @scene.property_channels().map(fn(channel) {
    (channel, channel_key(channel))
  })
  @core.object_keys(entries).map(fn(key) {
    let track = entries._get(key)
    let properties = []
    for (channel, name) in channels {
      let timing = track._get(name)
      if !@core.is_nullish(timing) {
        properties.push((channel, timing_range(timing)))
      }
    }
    {
      key,
      object_id: track._get("objectId").cast(),
      base: if @core.equal(track._get("implicit"), @core.any(true)) {
        None
      } else {
        Some(timing_range(track))
      },
      properties,
    }
  })
}

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
  if !@editor.valid_transition_duration(requested) {
    @core.throw_error(
      @boundary.animation_timing_error(@editor.TransitionBounds),
    )
    return
  }
  let entries = transition._get("tracks")
  let objects = scene._get("objects")
  let tracks = transition_timings(entries)
  let locked : Set[String] = Set([])
  for id in @core.object_keys(objects) {
    if truthy(objects._get(id)._get("locked")) {
      locked.add(id)
    }
  }
  match @editor.resize_transition(tracks, locked, requested) {
    Err(error) => @core.throw_error(@boundary.animation_timing_error(error))
    Ok(plan) =>
      edit(store, @boundary.transition_resize_changes(scene_id, id, plan))
  }
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
  edit(
    store,
    @boundary.single_track_changes(
      scene_id,
      transition_id,
      object_id,
      transition._get("tracks")._get(object_id),
      patch,
      number(transition._get("duration")),
    ),
    separate~,
  )
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
  let plan = @editor.property_timing_update(
    if truthy(current) {
      Some(@boundary.read_timing(current))
    } else {
      None
    },
    if truthy(timing) {
      Some(@boundary.read_timing(timing))
    } else {
      None
    },
    number(transition._get("duration")),
  )
  match plan {
    Err(error) => @core.throw_error(@boundary.animation_timing_error(error))
    Ok(KeepTiming) => ()
    Ok(plan) =>
      edit(
        store,
        @boundary.property_timing_changes(
          [
            "scenes", scene_id, "transitions", transition_id, "tracks", object_id,
            key,
          ],
          plan,
          timing,
        ),
        separate~,
      )
  }
}
