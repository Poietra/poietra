///|
priv struct MediaGesture {
  pointer : Int
  x : Double
  width : Double
  total : Double
  edge : @editor.TimingEdge
  before : @scene.MediaPlayback
  mut next : @scene.MediaPlayback
  clip : MediaClip
  element : @core.Any
}

///|
priv struct MediaController {
  store : @core.Any
  scene_id : String
  select : (String?) -> Unit
  selected_ids : (FixedArray[String]) -> Unit
  draft : (@scene.MediaPlayback?) -> Unit
  message : (String) -> Unit
  notify : (String) -> Unit
  mut drag : MediaGesture?
  mut busy : Bool
}

///|
fn MediaController::update(
  self : MediaController,
  clip : MediaClip,
  patch : @core.Any,
) -> Unit {
  if clip.locked {
    return
  }
  attempt(
    fn() {
      self.store._call(
        if clip.kind is AudioClip {
          "setAudioTrack"
        } else {
          "setVideoPlayback"
        },
        [@core.any(self.scene_id), @core.any(clip.id), patch],
      )
      |> ignore
      (self.message)(clip.name + " · タイミングを更新しました")
    },
    self.notify,
    "タイミングを変更できませんでした。",
  )
}

///|
fn MediaController::finish(self : MediaController, cancel : Bool) -> Unit {
  guard self.drag is Some(gesture) else { return }
  self.drag = None
  (self.draft)(None)
  if truthy(
      gesture.element._call("hasPointerCapture", [@core.any(gesture.pointer)]),
    ) {
    gesture.element._call("releasePointerCapture", [@core.any(gesture.pointer)])
    |> ignore
  }
  if cancel {
    (self.message)("タイミングの変更を取り消しました")
    return
  }
  let latest = self.store._call("scene", [@core.any(self.scene_id)])
  let current = media_clip(latest, gesture.clip.id, gesture.clip.kind)
  if current is Some(clip) && clip.locked {
    (self.message)("ロック中の動画は変更できません")
    return
  }
  if @boundary.scene_duration(latest).max(1000.0) != gesture.total {
    (self.message)(
      "タイムラインの長さが変わったため、操作を中止しました",
    )
    return
  }
  if current.map(fn(clip) { clip.timing == gesture.before }).unwrap_or(false) ==
    false {
    (self.notify)(
      "共同編集者がタイミングを変更しました。もう一度操作してください。",
    )
    return
  }
  if gesture.before != gesture.next {
    self.update(gesture.clip, playback_value(gesture.next))
  }
}

///|
fn MediaController::choose(self : MediaController, clip : MediaClip) -> Unit {
  if self.drag is Some(gesture) && gesture.clip.id != clip.id {
    self.finish(true)
  }
  (self.select)(Some(clip.id))
  (self.message)("")
  (self.selected_ids)(if clip.kind is VideoClip { [clip.id] } else { [] })
}

///|
fn pointer_edge(event : @core.Any) -> @editor.TimingEdge {
  let target = event._get("target")._call("closest", [@core.any("[data-edge]")])
  if !truthy(target) {
    return @editor.MoveTiming
  }
  let edge : String = target._get("dataset")._get("edge").cast()
  match edge {
    "start" => @editor.TrimStart
    "end" => @editor.TrimEnd
    _ => @editor.MoveTiming
  }
}

///|
fn MediaController::down(
  self : MediaController,
  event : @core.Any,
  clip : MediaClip,
) -> Unit {
  if event._get("button").cast() != 0 || self.drag is Some(_) {
    return
  }
  let element = event._get("currentTarget")
  element._call("focus", [host_record({ "preventScroll": @core.any(true) })])
  |> ignore
  self.choose(clip)
  let latest = self.store._call("scene", [@core.any(self.scene_id)])
  guard media_clip(latest, clip.id, clip.kind) is Some(current) else { return }
  if self.busy || current.locked {
    return
  }
  let width : Double = element
    ._get("parentElement")
    ._call("getBoundingClientRect", [])
    ._get("width")
    .cast()
  if width <= 0.0 {
    return
  }
  let gesture : MediaGesture = {
    pointer: event._get("pointerId").cast(),
    x: event._get("clientX").cast(),
    width,
    total: @boundary.scene_duration(latest).max(1000.0),
    edge: pointer_edge(event),
    before: current.timing,
    next: current.timing,
    clip: current,
    element,
  }
  self.drag = Some(gesture)
  let mut captured = true
  @core.ffi_wrap_sync(
    fn() { element._call("setPointerCapture", [@core.any(gesture.pointer)]) },
    fn(_) { () },
    fn(_) {
      captured = false
      self.finish(true)
    },
  )
  if !captured {
    return
  }
  (self.draft)(Some(current.timing))
  prevent_default(event)
}

///|
fn MediaController::pointer_move(
  self : MediaController,
  event : @core.Any,
) -> Unit {
  guard self.drag is Some(gesture) else { return }
  if event._get("pointerId").cast() != gesture.pointer {
    return
  }
  let x : Double = event._get("clientX").cast()
  let delta = round_number(
      (x - gesture.x) / gesture.width * gesture.total / 10.0,
    ) *
    10.0
  let next = @editor.media_gesture(
    gesture.before,
    gesture.edge,
    delta,
    gesture.clip.asset._get("duration").cast(),
  )
  gesture.next = next
  (self.draft)(Some(next))
  (self.message)(
    gesture.clip.name +
    " · " +
    media_seconds(next.start) +
    " → " +
    media_seconds(next.start + next.duration),
  )
}

///|
fn MediaController::end(
  self : MediaController,
  event : @core.Any,
  cancel : Bool,
) -> Unit {
  if self.drag is Some(gesture) &&
    gesture.pointer == event._get("pointerId").cast() {
    self.finish(cancel)
  }
}
