///|
/// Numeric host functions allow the JS renderer to use the same WASM kernel as export.
pub(all) struct Kernel {
  track_progress : (Double, Double, Double, Int) -> Double
  interpolate : (Double, Double, Double) -> Double
  cubic_bezier : (Double, Double, Double, Double, Double) -> Double
  cubic_bezier_ease : (Double, Double, Double, Double, Double) -> Double
  compare_ids : (String, String) -> Int
}

///|
fn progress(
  track : Track,
  timing : Timing?,
  time : Double,
  kernel : Kernel,
) -> Double {
  let timing = timing.unwrap_or({
    start: track.start,
    duration: track.duration,
    easing: track.easing,
  })
  if track.type_ == Cut {
    return if time >= timing.start + timing.duration { 1.0 } else { 0.0 }
  }
  timing_progress(timing, time, kernel)
}

///|
pub fn timing_progress(
  timing : Timing,
  time : Double,
  kernel : Kernel,
) -> Double {
  match timing.easing {
    CubicBezier(x1, y1, x2, y2) => {
      if time < timing.start {
        return 0.0
      }
      if timing.duration <= 0.0 {
        return 1.0
      }
      (kernel.cubic_bezier_ease)(
        (time - timing.start) / timing.duration,
        x1,
        y1,
        x2,
        y2,
      )
    }
    preset =>
      (kernel.track_progress)(
        time,
        timing.start,
        timing.duration,
        match preset {
          EaseInOut => 1
          EaseIn => 2
          EaseOut => 3
          _ => 0
        },
      )
  }
}

///|
fn hex_digit(c : UInt16) -> Int? {
  let c = c.to_int()
  if c >= 48 && c <= 57 {
    Some(c - 48)
  } else if c >= 65 && c <= 70 {
    Some(c - 55)
  } else if c >= 97 && c <= 102 {
    Some(c - 87)
  } else {
    None
  }
}

///|
fn parse_rgb(value : String) -> Array[Double]? {
  if value.length() != 7 || value[0] != 35 {
    return None
  }
  let result : Array[Double] = []
  for i in [1, 3, 5] {
    guard hex_digit(value[i]) is Some(a) else { return None }
    guard hex_digit(value[i + 1]) is Some(b) else { return None }
    result.push((a * 16 + b).to_double())
  }
  Some(result)
}

///|
fn prepare_color(from : String, to : String) -> ColorProgram {
  match (parse_rgb(from), parse_rgb(to)) {
    (Some(a), Some(b)) =>
      if from == to {
        Constant(from.to_lower())
      } else {
        Rgb(a[0], a[1], a[2], b[0], b[1], b[2])
      }
    _ => if from == to { Constant(from) } else { Discrete(from, to) }
  }
}

///|
fn color(program : ColorProgram, t : Double) -> String {
  match program {
    Constant(value) => value
    Discrete(from, to) => if t < 0.5 { from } else { to }
    Rgb(ar, ag, ab, br, bg, bb) => {
      let r = (ar * (1.0 - t) + br * t + 0.5).to_int()
      let g = (ag * (1.0 - t) + bg * t + 0.5).to_int()
      let b = (ab * (1.0 - t) + bb * t + 0.5).to_int()
      let hex = ((r << 16) | (g << 8) | b).to_string(radix=16)
      "#" + "000000"[0:6 - hex.length()].to_owned() + hex
    }
  }
}

///|
fn playback(object : SceneObject) -> MediaPlayback? {
  if object.kind != Video {
    return None
  }
  object.media.map(fn(media) {
    object.playback.unwrap_or({
      start: 0.0,
      offset: 0.0,
      duration: media.duration,
    })
  })
}

///|
fn video_active(object : SceneObject, time : Double) -> Bool {
  match playback(object) {
    None => true
    Some(p) => time >= p.start && time < p.start + p.duration
  }
}

///|
fn video_time(object : SceneObject, time : Double) -> Double? {
  playback(object).map(fn(p) {
    p.offset + clamp(time - p.start, 0.0, p.duration)
  })
}

///|
fn ordered_objects(
  scene : Scene,
  compare_ids : (String, String) -> Int,
) -> Array[SceneObject] {
  let objects = scene.objects.values().collect()
  objects.sort_by(fn(a, b) {
    if a.order < b.order {
      -1
    } else if a.order > b.order {
      1
    } else {
      compare_ids(a.id, b.id)
    }
  })
  objects
}

///|
fn frame(scene : Scene, objects : Array[RenderObject]) -> Frame {
  {
    background: scene.background,
    width: scene.width,
    height: scene.height,
    objects,
  }
}

///|
pub fn composition_frame(
  scene : Scene,
  composition : Composition,
  time : Double,
  compare_ids : (String, String) -> Int,
) -> Frame {
  frame(
    scene,
    composition_objects(ordered_objects(scene, compare_ids), composition, time),
  )
}

///|
/// Evaluate an authored still using only its states and ordered object metadata.
pub fn composition_objects(
  ordered : Array[SceneObject],
  composition : Composition,
  time : Double,
) -> Array[RenderObject] {
  let objects : Array[RenderObject] = []
  for object in ordered {
    if composition.states.get(object.id) is Some(state) && state.visible {
      objects.push({
        object,
        state,
        videoTimeMs: video_time(object, time),
        writeProgress: 1.0,
        order: "together",
      })
    }
  }
  objects
}

///|
pub fn prepare_transition(
  scene : Scene,
  transition : Transition,
  kernel : Kernel,
) -> PreparedTransition {
  guard scene.compositions.get(transition.fromId) is Some(from) else {
    return PreparedTransition::{ items: [], }
  }
  guard scene.compositions.get(transition.toId) is Some(to) else {
    return PreparedTransition::{ items: [], }
  }
  let items : Array[AnimatedObject] = []
  for object in ordered_objects(scene, kernel.compare_ids) {
    let a_state = from.states.get(object.id)
    let b_state = to.states.get(object.id)
    let a_visible = a_state.map(fn(s) { s.visible }).unwrap_or(false)
    let b_visible = b_state.map(fn(s) { s.visible }).unwrap_or(false)
    if !a_visible && !b_visible {
      continue
    }
    let (a, b) = match (a_state, b_state) {
      (Some(a), Some(b)) => (a, b)
      (Some(a), None) => (a, a)
      (None, Some(b)) => (b, b)
      _ => continue
    }
    let track = resolve_track(
      transition.tracks.get(object.id),
      object.id,
      transition.duration,
    )
    items.push({
      object,
      a,
      b,
      track,
      presence: if !a_visible {
        Entering
      } else if !b_visible {
        Leaving
      } else {
        Persistent
      },
      animation: track.type_,
      fill: prepare_color(a.fill, b.fill),
      stroke: prepare_color(a.stroke, b.stroke),
    })
  }
  PreparedTransition::{ items, }
}

///|
pub fn evaluate_transition(
  prepared : PreparedTransition,
  time : Double,
  scene_time : Double,
  kernel : Kernel,
) -> Array[RenderObject] {
  let objects : Array[RenderObject] = []
  for item in prepared.items {
    let { object, a, b, track, presence: visibility, animation, fill, stroke, } = item
    let (a_visible, b_visible) = match visibility {
      Persistent => (true, true)
      Entering => (false, true)
      Leaving => (true, false)
    }
    if !video_active(object, scene_time) {
      continue
    }
    let base = progress(track, None, time, kernel)
    let channel = fn(timing : Timing?) {
      if timing is None {
        base
      } else {
        progress(track, timing, time, kernel)
      }
    }
    let position = channel(track.positionTiming)
    let size = channel(track.sizeTiming)
    let shape_path = channel(track.pathTiming)
    let reveal = channel(track.revealTiming)
    let opacity = channel(track.opacityTiming)
    let interpolate = kernel.interpolate
    let path_point = fn(a : Point, b : Point) -> Point {
      {
        x: interpolate(a.x, b.x, shape_path),
        y: interpolate(a.y, b.y, shape_path),
      }
    }
    let mut state : ObjectState = {
      x: interpolate(a.x, b.x, position),
      y: interpolate(a.y, b.y, position),
      width: interpolate(a.width, b.width, size),
      height: interpolate(a.height, b.height, size),
      rotation: interpolate(
        a.rotation,
        b.rotation,
        channel(track.rotationTiming),
      ),
      opacity: interpolate(a.opacity, b.opacity, opacity),
      visible: true,
      fill: color(fill, channel(track.fillTiming)),
      stroke: color(stroke, channel(track.strokeTiming)),
      strokeWidth: interpolate(
        a.strokeWidth,
        b.strokeWidth,
        channel(track.strokeWidthTiming),
      ),
      fontSize: interpolate(
        a.fontSize,
        b.fontSize,
        channel(track.fontSizeTiming),
      ),
      cornerRadius: interpolate(
        a.cornerRadius,
        b.cornerRadius,
        channel(track.cornerRadiusTiming),
      ),
      text: if base < 0.5 {
        a.text
      } else {
        b.text
      },
      effect: if base < 0.5 {
        a.effect
      } else {
        b.effect
      },
      path: {
        c1: path_point(a.path.c1, b.path.c1),
        c2: path_point(a.path.c2, b.path.c2),
      },
    }
    if track.path is Some(path) && a_visible && b_visible {
      state = {
        ..state,
        x: (kernel.cubic_bezier)(a.x, path.c1.x, path.c2.x, b.x, position),
        y: (kernel.cubic_bezier)(a.y, path.c1.y, path.c2.y, b.y, position),
      }
    }
    let presence = if !a_visible {
      reveal
    } else if !b_visible {
      1.0 - reveal
    } else {
      1.0
    }
    if track.opacityTiming is Some(_) && (!a_visible || !b_visible) {
      state = {
        ..state,
        opacity: interpolate(
          if a_visible {
            a.opacity
          } else {
            0.0
          },
          if b_visible {
            b.opacity
          } else {
            0.0
          },
          opacity,
        ),
      }
    } else if animation != Write {
      state = {
        ..state,
        opacity: state.opacity *
        (if !a_visible {
          opacity
        } else if !b_visible {
          1.0 - opacity
        } else {
          1.0
        }),
      }
    }
    if animation == Write && presence == 0.0 {
      state = { ..state, opacity: 0.0, }
    }
    if animation == Grow && (!a_visible || !b_visible) {
      state = {
        ..state,
        width: state.width * presence,
        height: state.height * presence,
        fontSize: state.fontSize * presence,
      }
    }
    objects.push({
      object,
      state,
      videoTimeMs: video_time(object, scene_time),
      writeProgress: if animation == Write {
        if !b_visible {
          1.0 - reveal
        } else {
          reveal
        }
      } else {
        1.0
      },
      order: track.order,
    })
  }
  objects
}

///|
pub fn transition_frame(
  scene : Scene,
  transition : Transition,
  time : Double,
  scene_time : Double,
  kernel : Kernel,
) -> Frame {
  frame(
    scene,
    evaluate_transition(
      prepare_transition(scene, transition, kernel),
      time,
      scene_time,
      kernel,
    ),
  )
}

///|
pub fn evaluate_scene(scene : Scene, time : Double, kernel : Kernel) -> Frame {
  let segments = scene_segments(scene)
  guard segments.last() is Some(last) else { return frame(scene, []) }
  let mut current = last
  for segment in segments {
    if time < segment.start + segment.duration {
      current = segment
      break
    }
  }
  let result = if current.kind == "composition" {
    composition_frame(
      scene,
      scene.compositions[current.id],
      time,
      kernel.compare_ids,
    )
  } else {
    transition_frame(
      scene,
      scene.transitions[current.id],
      clamp(time - current.start, 0.0, current.duration),
      time,
      kernel,
    )
  }
  {
    ..result,
    objects: result.objects.filter(fn(item) { video_active(item.object, time) }),
  }
}
