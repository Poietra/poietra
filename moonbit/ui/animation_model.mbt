///|
priv struct AnimationTarget {
  scene_id : String
  transition_id : String
  object_id : String
}

///|
fn AnimationTarget::key(self : AnimationTarget) -> String {
  "\{self.scene_id}/\{self.transition_id}/\{self.object_id}"
}

///|
/// Only the selected animation is decoded. Shared document snapshots never
/// become mutable UI state or copies of an entire Scene.
priv struct AnimationSnapshot {
  kind : @scene.ObjectKind
  track : @scene.Track
  duration : Double
  locked : Bool
  visible : Bool
  keyframes_ready : Bool
}

///|
fn AnimationSnapshot::timing(
  self : AnimationSnapshot,
  channel : @scene.PropertyChannel,
) -> @scene.Timing {
  @scene.timing_override(self.track, channel).unwrap_or({
    start: self.track.start,
    duration: self.track.duration,
    easing: self.track.easing,
  })
}

///|
priv struct KeyframeEvaluation {
  curve : (@scene.CurveProperty) -> @scene.PreparedCurve?
  sample : (@scene.CurveProperty, Double, Double) -> @scene.CurveValue
  kernel : @scene.Kernel
}

///|
priv struct PropertyTimingView {
  animation : AnimationSnapshot
  binding : AnimationBinding
  evaluation : KeyframeEvaluation
}

///|
priv struct AnimationTimingEdit {
  timing : @scene.Timing
  limit : Double
  locked : Bool
  materialized : Bool
}

///|
/// Timeline rows carry presentation values, not decoded Track/keyframe maps.
priv struct TrackRowData {
  binding : AnimationBinding
  object_name : String
  object_kind : @scene.ObjectKind
  animation_label : String
  locked : Bool
  timing : @scene.Timing
  properties : Array[(@scene.PropertyChannel, @scene.Timing)]
  total : Double
}

///|
priv struct TrackRowView {
  data : TrackRowData
  channel : @scene.PropertyChannel?
  timing : @scene.Timing
  active : Bool
  report : (@editor.OperationStatus?) -> Unit
}

///|
priv struct KeyframeView {
  animation : AnimationSnapshot
  binding : AnimationBinding
  evaluation : KeyframeEvaluation
  channel : @scene.PropertyChannel
  disabled : Bool
}

///|
/// Read at command time: a rendered duration/easing may already have been
/// changed by a peer. Only the requested property is changed in the pure plan.
fn AnimationBinding::change_timing(
  self : AnimationBinding,
  channel : @scene.PropertyChannel,
  patch : @editor.PropertyTimingChange,
  separate : Bool,
) -> Unit {
  guard self.property_timing(channel) is Some(current) && !current.locked else {
    return
  }
  self.set_timing(
    channel,
    @editor.change_property_timing(current.timing, patch, current.limit),
    separate,
  )
}
