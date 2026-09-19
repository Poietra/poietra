///|
pub suberror CompileError {
  CompileError(String)
}

///|
pub(all) enum IdentityKind {
  ObjectRef
  CompositionRef
  TransitionRef
} derive(Eq)

///|
pub(all) enum Scalar {
  Number(Double)
  Text(String)
  Boolean(Bool)
}

///|
pub(all) enum StateField {
  X
  Y
  Width
  Height
  Rotation
  Opacity
  Visible
  Fill
  Stroke
  StrokeWidth
  TextContent
  FontSize
  CornerRadius
  Effect
} derive(Eq)

///|
pub(all) enum TrackEdit {
  Kind(@scene.AnimationKind)
  Start(Double)
  Duration(Double)
  Easing(@scene.Easing)
  Order(String)
  MotionPath(@scene.Bezier?)
  PropertyTiming(@scene.PropertyChannel, @scene.Timing?)
}

///|
pub(all) struct Creation {
  reference : String?
  composition : String
  name : String
  kind : @scene.ObjectKind
  state : @scene.ObjectState
  image : @scene.ImageAsset?
}

///|
pub(all) enum Operation {
  Create(Creation)
  Append(String, String, String, Double, Double)
  State(String, String, StateField, Scalar)
  ShapePath(String, String, @scene.Bezier)
  Track(String, String, TrackEdit)
  CompositionDuration(String, Double)
  TransitionDuration(String, Double)
}

///|
pub(all) struct CompositionInfo {
  id : String
  name : String
  duration : Double
  accent : String
  state_ids : Array[String]
}

///|
pub(all) struct TransitionInfo {
  id : String
  from_id : String
  to_id : String
  duration : Double
  track_ids : Array[String]
}

///|
/// The source exposes metadata and lazy immutable reads. A one-property edit
/// never copies or decodes the rest of a Scene's object states or animations.
pub(all) struct Source {
  objects : Map[String, @scene.SceneObject]
  compositions : Map[String, CompositionInfo]
  transitions : Map[String, TransitionInfo]
  order : Array[String]
  raw_composition_ids : Array[String]
  deleted_compositions : Set[String]
  state : (String, String) -> @scene.ObjectState?
  track : (String, String) -> @scene.Track?
}

///|
pub(all) enum Value {
  ScalarValue(Scalar)
  EasingValue(@scene.Easing)
  PathValue(@scene.Bezier?)
  TimingValue(@scene.Timing?)
  StateValue(@scene.ObjectState)
  ObjectValue(@scene.SceneObject)
  TrackValue(@scene.Track, Array[@scene.PropertyChannel])
  CompositionValue(@scene.Composition)
  TransitionValue(@scene.Transition, Map[String, Array[@scene.PropertyChannel]])
}

///|
pub(all) struct Change {
  path : Array[String]
  value : Value
}

///|
pub(all) struct Plan {
  changes : Array[Change]
  guards : Array[Array[String]]
  appended : Array[String]
}

///|
priv struct PendingObject {
  object : @scene.SceneObject
  state : @scene.ObjectState
  composition : String
  mut declared : Bool
}

///|
priv struct EditedTrack {
  transition : String
  object_id : String
  path : Array[String]
  duration : Double
  existing : Bool
  mut value : @scene.Track
  mut motion_edited : Bool
  timing_fields : Array[@scene.PropertyChannel]
}

///|
priv struct Compiler {
  source : Source
  objects : Map[String, @scene.SceneObject]
  compositions : Map[String, CompositionInfo]
  transitions : Map[String, TransitionInfo]
  order : Array[String]
  states : Map[String, Map[String, @scene.ObjectState]]
  references : Map[String, (String, IdentityKind)]
  declarations : Map[Int, String]
  created : Map[String, PendingObject]
  appended : Array[String]
  new_transitions : Set[String]
  durations : Map[String, Double]
  tracks : Map[(String, String), EditedTrack]
  changes : Array[Change]
  guards : Array[Array[String]]
}
