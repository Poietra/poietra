///|
#external
priv type AnimationStore

///|
priv struct AnimationBinding {
  store : AnimationStore
  target : AnimationTarget
}

///|
fn native_animation_binding(
  store : @core.Any,
  target : AnimationTarget,
) -> AnimationBinding {
  { store: store.cast(), target, }
}

///|
fn native_animation_snapshot(
  scene : @core.Any,
  object : @core.Any,
  transition : @core.Any,
  track : @scene.Track,
) -> AnimationSnapshot {
  let id : String = object._get("id").cast()
  {
    kind: @boundary.read_object_kind(object._get("kind")),
    track,
    duration: transition._get("duration").cast(),
    locked: truthy(object._get("locked")),
    visible: truthy(@boundary.visible_animation(scene, transition, id)),
    keyframes_ready: truthy(
      transition._get("tracks")._get(id)._get("keyframes"),
    ),
  }
}

///|
fn AnimationBinding::current(
  self : AnimationBinding,
) -> (@core.Any, @core.Any)? {
  // Exact lookup, without store.scene's fallback to another Scene after deletion.
  let scene = @core.any(self.store)
    ._call("project", [])
    ._get("scenes")
    ._get(self.target.scene_id)
  if !truthy(scene) {
    return None
  }
  let transition = scene._get("transitions")._get(self.target.transition_id)
  if !truthy(transition) {
    return None
  }
  let animation = @boundary.visible_animation(
    scene,
    transition,
    self.target.object_id,
  )
  if !truthy(animation) {
    return None
  }
  Some((transition, animation))
}

///|
/// Convert the resolved timing here, including after peer edits. Gesture logic
/// receives timing values without carrying a native Track or its keyframes.
fn AnimationBinding::property_timing(
  self : AnimationBinding,
  channel : @scene.PropertyChannel,
) -> PropertyTimingEdit? {
  self
  .current()
  .map(fn(current) {
    let (transition, animation) = current
    {
      timing: @boundary.read_timing(
        @boundary.get_property_timing(
          animation._get("track"),
          @editor.property_channel_name(channel),
        ),
      ),
      limit: transition._get("duration").cast(),
      locked: truthy(animation._get("object")._get("locked")),
    }
  })
}

///|
fn AnimationBinding::easing(self : AnimationBinding) -> @scene.Easing? {
  self
  .current()
  .map(fn(current) {
    @boundary.read_easing(current.1._get("track")._get("easing"))
  })
}

///|
fn AnimationBinding::keyframe_easing(
  self : AnimationBinding,
  id : String,
) -> @scene.Easing? {
  guard self.current() is Some((_, animation)) else { return None }
  let key = animation._get("track")._get("keyframes")._get(id)
  if !truthy(key) || truthy(key._get("deleted")) {
    return None
  }
  Some(@boundary.read_easing(key._get("easing")))
}

///|
fn AnimationBinding::set_timing(
  self : AnimationBinding,
  channel : @scene.PropertyChannel,
  timing : @scene.Timing?,
  separate : Bool,
) -> Unit {
  @core.any(self.store)._call("setPropertyTiming", [
    @core.any(self.target.scene_id),
    @core.any(self.target.transition_id),
    @core.any(self.target.object_id),
    @core.any(@editor.property_channel_name(channel)),
    timing.map(@boundary.write_timing).unwrap_or(@core.null()),
    @core.any(separate),
  ])
  |> ignore
}

///|
fn AnimationBinding::set_easing(
  self : AnimationBinding,
  easing : @scene.Easing,
  separate : Bool,
) -> Unit {
  @core.any(self.store)._call("setTrack", [
    @core.any(self.target.scene_id),
    @core.any(self.target.transition_id),
    @core.any(self.target.object_id),
    host_record({ "easing": @boundary.write_easing(easing) }),
    @core.any(separate),
  ])
  |> ignore
}

///|
fn AnimationBinding::keyframe_patch(
  self : AnimationBinding,
  id : String,
  patch : @core.Any,
  separate : Bool,
) -> Unit {
  @core.any(self.store)._call("setKeyframe", [
    @core.any(self.target.scene_id),
    @core.any(self.target.transition_id),
    @core.any(self.target.object_id),
    @core.any(id),
    patch,
    @core.any(separate),
  ])
  |> ignore
}

///|
fn AnimationBinding::add_keyframe(
  self : AnimationBinding,
  key : @scene.Keyframe,
) -> Unit {
  self.keyframe_patch(
    @boundary.new_id("key"),
    @boundary.write_keyframe(key),
    true,
  )
}

///|
fn AnimationBinding::remove_keyframe(
  self : AnimationBinding,
  id : String,
) -> Unit {
  self.keyframe_patch(id, @core.null(), true)
}

///|
fn AnimationBinding::set_keyframe_at(
  self : AnimationBinding,
  id : String,
  at : Double,
) -> Unit {
  self.keyframe_patch(id, host_record({ "at": @core.any(at) }), true)
}

///|
fn AnimationBinding::set_keyframe_value(
  self : AnimationBinding,
  id : String,
  value : @scene.CurveValue,
) -> Unit {
  let value = match value {
    CurveNumber(value) => @core.any(value)
    CurveColor(value) => @core.any(value)
  }
  self.keyframe_patch(id, host_record({ "value": value }), true)
}

///|
fn AnimationBinding::set_keyframe_easing(
  self : AnimationBinding,
  id : String,
  easing : @scene.Easing,
  separate : Bool,
) -> Unit {
  self.keyframe_patch(
    id,
    host_record({ "easing": @boundary.write_easing(easing) }),
    separate,
  )
}

///|
fn native_property_timing_view(
  editor : EditorView,
  object : @core.Any,
  transition : @core.Any,
  track : @scene.Track,
) -> PropertyTimingView {
  let scene = editor.scene
  let id : String = object._get("id").cast()
  let animation = native_animation_snapshot(scene, object, transition, track)
  {
    animation,
    binding: native_animation_binding(editor.store, {
      scene_id: scene._get("id").cast(),
      transition_id: transition._get("id").cast(),
      object_id: id,
    }),
    evaluation: {
      kernel: @boundary.read_kernel(editor.kernel),
      curve: fn(property) {
        @boundary.keyframe_curve(scene, transition, id, property)
      },
      sample: fn(property, time, at) {
        let frame = @boundary.transition_frame(
          scene,
          transition,
          time,
          editor.kernel,
          @core.undefined(),
        )
        let objects : FixedArray[@core.Any] = frame._get("objects").cast()
        let item = objects
          .iter()
          .find_first(fn(item) {
            string_value(item._get("object")._get("id")) == id
          })
        match item {
          Some(item) =>
            if property is ObjectReveal {
              @scene.CurveNumber(at)
            } else {
              @scene.state_curve_value(
                @boundary.read_object_state(item._get("state")),
                property,
              )
            }
          None =>
            @scene.state_curve_value(
              @scene.default_state(animation.kind),
              property,
            )
        }
      },
    },
  }
}

///|
pub fn property_timing_inspector(input : @core.Any) -> @react.Element {
  render_property_timing(
    native_property_timing_view(
      use_editor_state(),
      input._get("object"),
      input._get("transition"),
      @boundary.read_track(input._get("track")),
    ),
  )
}
