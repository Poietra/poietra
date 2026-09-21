///|
fn group_objects(scene : @core.Any) -> Array[@editor.GroupObject] {
  let objects = scene._get("objects")
  @core.object_keys(objects).map(fn(id) {
    let object = objects._get(id)
    {
      id: object._get("id").cast(),
      group_id: @project_codec.optional(object._get("groupId"), fn(v) {
        v.cast()
      }),
      locked: truthy(object._get("locked")),
      order: object._get("order").cast(),
    }
  })
}

///|
fn object_values(
  scene : @core.Any,
  ids : Array[String],
) -> FixedArray[@core.Any] {
  let objects = scene._get("objects")
  FixedArray::makei(ids.length(), fn(i) { objects._get(ids[i]) })
}

///|
pub fn group_members(
  scene : @core.Any,
  group_id : String,
) -> FixedArray[@core.Any] {
  object_values(scene, @editor.group_members(group_objects(scene), group_id))
}

///|
pub fn editable_group_members(
  scene : @core.Any,
  ids : FixedArray[String],
) -> FixedArray[@core.Any] {
  object_values(
    scene,
    @editor.editable_group_members(
      group_objects(scene),
      Array::makei(ids.length(), fn(i) { ids[i] }),
    ),
  )
}

///|
fn state_visible(
  scene : @core.Any,
  composition : String,
  object_id : String,
) -> Bool {
  let state = state_for(scene, composition, object_id)
  !@core.is_nullish(state) && truthy(state._get("visible"))
}

///|
extern "js" fn make_animation(
  object : @core.Any,
  track : @core.Any,
  existing : Bool,
  presence : String,
) -> @core.Any =
  #|(object, track, existing, presence) => ({object, track, existing, presence})

///|
pub fn visible_animation(
  scene : @core.Any,
  transition : @core.Any,
  object_id : String,
) -> @core.Any {
  let object = scene._get("objects")._get(object_id)
  if !truthy(object) {
    return @core.null()
  }
  let from = state_visible(scene, transition._get("fromId").cast(), object_id)
  let to = state_visible(scene, transition._get("toId").cast(), object_id)
  match @editor.presence(from, to) {
    None => @core.null()
    Some(presence) => {
      let track = transition._get("tracks")._get(object_id)
      make_animation(
        object,
        resolve_track(track, object_id, transition._get("duration").cast()),
        truthy(track) && !truthy(track._get("implicit")),
        @editor.presence_name(presence),
      )
    }
  }
}

///|
pub fn visible_animations(
  scene : @core.Any,
  transition : @core.Any,
) -> FixedArray[@core.Any] {
  let result = []
  for object in ordered_objects(scene) {
    let animation = visible_animation(
      scene,
      transition,
      object._get("id").cast(),
    )
    if !@core.is_nullish(animation) {
      result.push(animation)
    }
  }
  FixedArray::makei(result.length(), fn(i) { result[i] })
}

///|
extern "js" fn excluded_target(
  object : @core.Any,
  reason : String,
) -> @core.Any =
  #|(object, reason) => ({object, reason})

///|
extern "js" fn animation_targets(
  targets : FixedArray[@core.Any],
  excluded : FixedArray[@core.Any],
) -> @core.Any =
  #|(targets, excluded) => ({targets, excluded})

///|
fn select_animations(
  scene : @core.Any,
  transition : @core.Any,
  selected : FixedArray[String],
) -> @editor.AnimationSelection {
  let objects = scene._get("objects")
  let from : String = transition._get("fromId").cast()
  let to : String = transition._get("toId").cast()
  let candidates : Array[@editor.AnimationCandidate] = []
  for id in selected {
    let object = objects._get(id)
    if !@core.is_nullish(object) {
      candidates.push({
        id,
        locked: truthy(object._get("locked")),
        from_visible: state_visible(scene, from, id),
        to_visible: state_visible(scene, to, id),
      })
    }
  }
  @editor.select_animations(candidates)
}

///|
pub fn group_animation_targets(
  scene : @core.Any,
  transition_id : String,
  selected : FixedArray[String],
) -> @core.Any {
  let transition = scene._get("transitions")._get(transition_id)
  if !truthy(transition) {
    return animation_targets([], [])
  }
  let selection = select_animations(scene, transition, selected)
  let objects = scene._get("objects")
  let tracks = transition._get("tracks")
  animation_targets(
    FixedArray::makei(selection.targets.length(), fn(i) {
      let (id, presence) = selection.targets[i]
      let track = tracks._get(id)
      make_animation(
        objects._get(id),
        resolve_track(track, id, transition._get("duration").cast()),
        truthy(track) && !truthy(track._get("implicit")),
        @editor.presence_name(presence),
      )
    }),
    FixedArray::makei(selection.excluded.length(), fn(i) {
      let (id, reason) = selection.excluded[i]
      excluded_target(
        objects._get(id),
        match reason {
          Locked => "locked"
          Hidden => "hidden"
        },
      )
    }),
  )
}

///|
fn patch_number(value : @core.Any) -> Double {
  if @core.typeof_(value) == "number" {
    value.cast()
  } else {
    0.0 / 0.0
  }
}

///|
fn decode_track_patch(value : @core.Any) -> Array[@editor.TrackField] {
  let result = []
  let kind = value._get("type")
  if !@core.is_undefined(kind) &&
    (
      @core.typeof_(kind) != "string" ||
      @scene.animation_kind(kind.cast()) is None
    ) {
    @core.throw_error(
      "アニメーションの種類を選択してください。",
    )
  }
  let curve = value._get("easing")
  if !@core.is_undefined(curve) && !is_valid_easing(curve) {
    @core.throw_error("Easing を選択してください。")
  }
  let order = value._get("order")
  if !@core.is_undefined(order) &&
    !strict_equal(order, @core.any("together")) &&
    !strict_equal(order, @core.any("sequential")) {
    @core.throw_error("Write の順序を選択してください。")
  }
  for key in @core.object_keys(value) {
    let item = value._get(key)
    if @core.is_undefined(item) {
      continue
    }
    match key {
      "type" =>
        result.push(@editor.Kind(@project_codec.decode_AnimationKind(item)))
      "start" => result.push(@editor.Start(patch_number(item)))
      "duration" => result.push(@editor.Duration(patch_number(item)))
      "easing" => result.push(@editor.Curve(@project_codec.decode_Easing(item)))
      "order" =>
        result.push(
          @editor.Order(
            if strict_equal(item, @core.any("together")) {
              @editor.Together
            } else {
              @editor.Sequential
            },
          ),
        )
      _ =>
        @core.throw_error(
          "アニメーションで変更できない属性です。",
        )
    }
  }
  result
}

///|
fn encode_track_value(value : @editor.TrackValue) -> @core.Any {
  match value {
    Whole(track) => track_value(track)
    Flag(value) => @core.any(value)
    Field(field) =>
      match field {
        Kind(kind) => @core.any(@scene.animation_name(kind))
        Start(value) | Duration(value) => @core.any(value)
        Curve(value) => @project_codec.encode_Easing(value)
        Order(value) => @core.any(@editor.write_order_name(value))
      }
  }
}

///|
pub fn group_animation_changes(
  scene : @core.Any,
  transition_id : String,
  selected : FixedArray[String],
  input : @core.Any,
) -> FixedArray[@core.Any] {
  let transition = scene._get("transitions")._get(transition_id)
  if !truthy(transition) {
    return []
  }
  let selection = select_animations(scene, transition, selected)
  let patch = decode_track_patch(input)
  let tracks = transition._get("tracks")
  let targets = selection.targets.map(fn(entry) {
    let (object_id, _) = entry
    @editor.EditableTrack::{
      object_id,
      stored: @project_codec.optional(
        tracks._get(object_id),
        @project_codec.decode_Track,
      ),
    }
  })
  match
    @editor.group_animation_plan(
      targets,
      transition._get("duration").cast(),
      patch,
    ) {
    Err(error) => {
      let message = match error {
        BaseBounds =>
          "開始時刻と長さが Transition の範囲を超えます。先に長さを短くするか、開始時刻を早めてください。"
        PropertyBounds =>
          "アニメーションの開始時刻と長さが Transition の範囲を超えています。"
        InvalidEasing =>
          "イージングの形式が無効です。ベジェ曲線の制御点は 0〜1 で指定してください。"
      }
      @core.throw_error(message)
      []
    }
    Ok(edits) =>
      FixedArray::makei(edits.length(), fn(i) {
        let edit = edits[i]
        let path : Array[String] = [
          "scenes",
          scene._get("id").cast(),
          "transitions",
          transition_id,
          "tracks",
          edit.object_id,
        ]
        if edit.key is Some(key) {
          path.push(key)
        }
        make_change(
          FixedArray::makei(path.length(), fn(j) { path[j] }),
          encode_track_value(edit.value),
        )
      })
  }
}

///|
pub fn common_track_value(
  targets : FixedArray[@core.Any],
  property : String,
) -> @core.Any {
  if targets.length() == 0 {
    return @core.undefined()
  }
  let first = targets[0]._get("track")._get(property)
  for target in targets {
    let value = target._get("track")._get(property)
    let equal = if property == "easing" {
      easings_equal(value, first)
    } else {
      same_value(value, first)
    }
    if !equal {
      return @core.undefined()
    }
  }
  first
}
