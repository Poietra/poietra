///|
/// The playback program owns a typed snapshot; clocks and presence are not part of it.
pub struct PreparedScene {
  scene : Scene
  priv schedule : Array[ScheduledSegment]
  holds : Map[String, Array[RenderObject]]
  changes : Map[String, PreparedTransition]
  starts : Map[String, Double]
  kernel : Kernel
  monotone : Bool
}

///|
/// Each segment has exactly one evaluation mode.
priv enum PlaybackSegment {
  Hold(Array[RenderObject])
  Change(PreparedTransition)
}

///|
priv struct ScheduledSegment {
  start : Double
  end : Double
  duration : Double
  program : PlaybackSegment
  static_frame : Bool
}

///|
priv struct AnimatedObject {
  object : SceneObject
  a : ObjectState
  b : ObjectState
  track : Track
  presence : Presence
  animation : AnimationKind
  fill : ColorProgram
  stroke : ColorProgram
  curves : Array[PreparedCurve]
}

///|
/// Hidden-at-both-endpoints objects are excluded during compilation.
priv enum Presence {
  Persistent
  Entering
  Leaving
  Hidden
}

///|
/// Parsed once; the hot loop never parses authored color strings.
priv enum ColorProgram {
  Constant(String)
  Rgb(Double, Double, Double, Double, Double, Double)
  Discrete(String, String)
}

///|
pub struct PreparedTransition {
  priv items : Array[AnimatedObject]
  priv hierarchy : Hierarchy?
}

///|
/// Sorting, track resolution, object matching, and timeline assembly happen once.
pub fn prepare_scene(scene : Scene, kernel : Kernel) -> PreparedScene {
  let holds : Map[String, Array[RenderObject]] = Map([])
  let changes : Map[String, PreparedTransition] = Map([])
  let starts : Map[String, Double] = Map([])
  let schedule : Array[ScheduledSegment] = []
  for id, composition in scene.compositions {
    holds[id] = composition_frame(scene, composition, 0.0, kernel.compare_ids).objects
  }
  for id, transition in scene.transitions {
    changes[id] = prepare_transition(scene, transition, kernel)
  }
  let mut monotone = true
  for segment in scene_segments(scene) {
    starts[segment.id] = segment.start
    if segment.duration < 0.0 ||
      segment.duration.is_nan() ||
      segment.duration.is_inf() {
      monotone = false
    }
    let program = if segment.kind == "composition" {
      Hold(holds[segment.id])
    } else {
      Change(changes[segment.id])
    }
    schedule.push({
      start: segment.start,
      end: segment.start + segment.duration,
      duration: segment.duration,
      program,
      static_frame: match program {
        Hold(objects) => !objects.any(fn(item) { item.object.kind == Video })
        Change(_) => false
      },
    })
  }
  { scene, schedule, holds, changes, starts, kernel, monotone, }
}

///|
fn evaluate_hold(
  objects : Array[RenderObject],
  time : Double,
  filter_video : Bool,
) -> Array[RenderObject] {
  let result : Array[RenderObject] = []
  for item in objects {
    if filter_video && !video_active(item.object, time) {
      continue
    }
    if item.object.kind == Video {
      result.push({ ..item, videoTimeMs: video_time(item.object, time), })
    } else {
      result.push(item)
    }
  }
  result
}

///|
/// Binary search gives time-addressable seeks without scanning all compositions.
fn PreparedScene::segment_index(self : PreparedScene, time : Double) -> Int? {
  if self.schedule.is_empty() {
    return None
  }
  let mut index = self.schedule.length() - 1
  if self.monotone {
    let mut low = 0
    let mut high = self.schedule.length()
    while low < high {
      let mid = low + (high - low) / 2
      if time < self.schedule[mid].end {
        high = mid
      } else {
        low = mid + 1
      }
    }
    index = low.min(index)
  } else {
    // Preserve diagnostics at the export boundary for malformed legacy durations.
    for i, segment in self.schedule {
      if time < segment.end {
        index = i
        break
      }
    }
  }
  Some(index)
}

///|
/// A key is valid only within this immutable program. Video remains time-dependent,
/// including its appearance/disappearance during an otherwise static hold.
pub fn PreparedScene::static_frame_key(
  self : PreparedScene,
  time : Double,
) -> Int? {
  match self.segment_index(time) {
    None => Some(-1)
    Some(index) =>
      if self.schedule[index].static_frame {
        Some(index)
      } else {
        None
      }
  }
}

///|
pub fn PreparedScene::evaluate(self : PreparedScene, time : Double) -> Frame {
  guard self.segment_index(time) is Some(index) else {
    return frame(self.scene, [])
  }
  let selected = self.schedule[index]
  let objects = match selected.program {
    Hold(objects) => evaluate_hold(objects, time, true)
    Change(transition) =>
      evaluate_transition(
        transition,
        clamp(time - selected.start, 0.0, selected.duration),
        time,
        self.kernel,
      )
  }
  frame(self.scene, objects)
}

///|
pub fn PreparedScene::composition(
  self : PreparedScene,
  id : String,
  time : Double?,
) -> Frame {
  let time = time.unwrap_or(self.starts.get(id).unwrap_or(0.0))
  frame(
    self.scene,
    evaluate_hold(self.holds.get(id).unwrap_or([]), time, false),
  )
}

///|
pub fn PreparedScene::transition(
  self : PreparedScene,
  id : String,
  time : Double,
  scene_time : Double?,
) -> Frame {
  let scene_time = scene_time.unwrap_or(
    self.starts.get(id).unwrap_or(0.0) + time,
  )
  let objects = match self.changes.get(id) {
    None => []
    Some(program) => evaluate_transition(program, time, scene_time, self.kernel)
  }
  frame(self.scene, objects)
}
