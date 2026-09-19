///|
fn with_timing(
  track : @scene.Track,
  channel : @scene.PropertyChannel,
  timing : @scene.Timing?,
) -> @scene.Track {
  match channel {
    Position => { ..track, positionTiming: timing, }
    Opacity => { ..track, opacityTiming: timing, }
    Size => { ..track, sizeTiming: timing, }
    Rotation => { ..track, rotationTiming: timing, }
    Fill => { ..track, fillTiming: timing, }
    Stroke => { ..track, strokeTiming: timing, }
    StrokeWidth => { ..track, strokeWidthTiming: timing, }
    FontSize => { ..track, fontSizeTiming: timing, }
    CornerRadius => { ..track, cornerRadiusTiming: timing, }
    ShapePath => { ..track, pathTiming: timing, }
    Reveal => { ..track, revealTiming: timing, }
  }
}

///|
fn Compiler::edit_track(
  self : Compiler,
  reference : String,
  object_reference : String,
  edit : TrackEdit,
) -> Unit raise CompileError {
  let tid = self.resolve(reference, TransitionRef)
  let oid = self.resolve(object_reference, ObjectRef)
  let (entry, transition) = self.editable_track(tid, oid)
  if edit is PropertyTiming(channel, timing) {
    if !entry.existing &&
      !self.created.contains(oid) &&
      !self.new_transitions.contains(tid) {
      raise CompileError(
        "アニメーションを準備しています。同期完了後にもう一度依頼してください。",
      )
    }
    entry.value = with_timing(entry.value, channel, timing)
    if !entry.timing_fields.contains(channel) {
      entry.timing_fields.push(channel)
    }
    if entry.existing {
      self.emit(
        entry.path + [@editor.property_channel_name(channel) + "Timing"],
        TimingValue(timing),
      )
    }
    return
  }
  if entry.value.implicit == Some(true) {
    entry.value = {
      ..@scene.resolve_track(Some(entry.value), oid, entry.duration),
      implicit: if entry.existing {
        Some(false)
      } else {
        None
      },
    }
    if entry.existing {
      self.emit(entry.path + ["start"], ScalarValue(Number(entry.value.start)))
      self.emit(
        entry.path + ["duration"],
        ScalarValue(Number(entry.value.duration)),
      )
      self.emit(entry.path + ["implicit"], ScalarValue(Boolean(false)))
    }
  }
  let (key, value, track) = match edit {
    Kind(kind) =>
      (
        "type",
        ScalarValue(Text(@scene.animation_name(kind))),
        { ..entry.value, type_: kind, },
      )
    Start(start) => {
      if !@assets.bounded_number(start, 0.0, entry.duration) {
        raise CompileError(
          "アニメーションの開始時刻が Transition の範囲を超えています。",
        )
      }
      ("start", ScalarValue(Number(start)), { ..entry.value, start, })
    }
    Duration(duration) => {
      if !@assets.bounded_number(duration, 0.0, entry.duration) {
        raise CompileError(
          "アニメーションの長さが Transition の範囲を超えています。",
        )
      }
      ("duration", ScalarValue(Number(duration)), { ..entry.value, duration, })
    }
    Easing(easing) =>
      ("easing", EasingValue(easing), { ..entry.value, easing, })
    Order(order) =>
      ("order", ScalarValue(Text(order)), { ..entry.value, order, })
    MotionPath(path) => {
      entry.motion_edited = true
      if entry.existing {
        self.depend(entry.path + ["type"])
      }
      if !self.created.contains(oid) {
        for cid in [transition.from_id, transition.to_id] {
          if !self.appended.contains(cid) {
            for key in ["x", "y", "visible"] {
              self.depend(["compositions", cid, "states", oid, key])
            }
          }
        }
      }
      ("path", PathValue(path), { ..entry.value, path, })
    }
    PropertyTiming(_, _) =>
      abort("Timing is handled before base-track promotion")
  }
  entry.value = track
  if entry.existing {
    self.emit(entry.path + [key], value)
  }
}

///|
fn check_track(track : @scene.Track, limit : Double) -> Unit raise CompileError {
  let resolved = @scene.resolve_track(Some(track), track.objectId, limit)
  let timings = [
    Some(@scene.Timing::{
      start: resolved.start,
      duration: resolved.duration,
      easing: resolved.easing,
    }),
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
  ]
  for timing in timings {
    if timing is Some(timing) {
      if !@scene.valid_timing_bounds(timing.start, timing.duration, limit) {
        raise CompileError(
          "アニメーションの開始時刻と長さが Transition の範囲を超えています。",
        )
      }
      if !@scene.valid_easing(timing.easing) {
        raise CompileError(
          "イージングの形式が無効です。ベジェ曲線の制御点は 0〜1 で指定してください。",
        )
      }
    }
  }
}
