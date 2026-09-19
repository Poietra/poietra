///|
pub(all) struct Point {
  x : Double
  y : Double
} derive(Eq, FromJson, ToJson)

///|
pub(all) struct Bezier {
  c1 : Point
  c2 : Point
} derive(Eq, FromJson, ToJson)

///|
pub(all) enum Easing {
  Linear
  EaseInOut
  EaseIn
  EaseOut
  CubicBezier(Double, Double, Double, Double)
} derive(Eq)

///|
pub impl @json.FromJson for Easing with fn from_json(json, path) {
  match json {
    String("linear") => Linear
    String("easeInOut") => EaseInOut
    String("easeIn") => EaseIn
    String("easeOut") => EaseOut
    Object(fields) => {
      let value : Curve = @json.from_json(json, path~)
      if value.type_ != "cubicBezier" || fields.length() != 5 {
        raise @json.JsonDecodeError((path, "Invalid easing"))
      }
      CubicBezier(value.x1, value.y1, value.x2, value.y2)
    }
    _ => raise @json.JsonDecodeError((path, "Invalid easing"))
  }
}

///|
priv struct Curve {
  type_ : String
  x1 : Double
  y1 : Double
  x2 : Double
  y2 : Double
} derive(FromJson(fields(type_(rename="type"))))

///|
pub impl ToJson for Easing with fn to_json(self) {
  match self {
    Linear => "linear"
    EaseInOut => "easeInOut"
    EaseIn => "easeIn"
    EaseOut => "easeOut"
    CubicBezier(x1, y1, x2, y2) =>
      { "type": "cubicBezier", "x1": x1, "y1": y1, "x2": x2, "y2": y2 }
  }
}

///|
pub(all) struct ObjectState {
  x : Double
  y : Double
  width : Double
  height : Double
  rotation : Double
  opacity : Double
  visible : Bool
  fill : String
  stroke : String
  strokeWidth : Double
  text : String
  fontSize : Double
  cornerRadius : Double
  effect : Effect
  path : Bezier
} derive(Eq, FromJson, ToJson)

///|
pub(all) struct ImageAsset {
  src : String
  width : Double
  height : Double
} derive(FromJson, ToJson)

///|
pub(all) struct MediaAsset {
  src : String
  mime : String
  duration : Double
  width : Double?
  height : Double?
  hasAudio : Bool
  waveform : Array[Double]?
} derive(FromJson, ToJson)

///|
pub(all) struct MediaPlayback {
  start : Double
  offset : Double
  duration : Double
} derive(Eq, Debug, FromJson, ToJson)

///|
pub(all) struct SceneObject {
  id : String
  name : String
  kind : ObjectKind
  order : Double
  groupId : String?
  locked : Bool
  image : ImageAsset?
  media : MediaAsset?
  playback : MediaPlayback?
} derive(FromJson, ToJson)

///|
pub(all) struct Composition {
  id : String
  name : String
  duration : Double
  accent : String
  states : Map[String, ObjectState]
  deleted : Bool?
  incomingTransitionId : String?
} derive(FromJson, ToJson)

///|
pub(all) struct Timing {
  start : Double
  duration : Double
  easing : Easing
} derive(FromJson, ToJson)

///|
pub(all) struct Track {
  implicit : Bool?
  objectId : String
  type_ : AnimationKind
  start : Double
  duration : Double
  easing : Easing
  order : String
  path : Bezier?
  positionTiming : Timing?
  opacityTiming : Timing?
  sizeTiming : Timing?
  rotationTiming : Timing?
  fillTiming : Timing?
  strokeTiming : Timing?
  strokeWidthTiming : Timing?
  fontSizeTiming : Timing?
  cornerRadiusTiming : Timing?
  pathTiming : Timing?
  revealTiming : Timing?
} derive (
  FromJson(fields(type_(rename="type"))),
  ToJson(fields(type_(rename="type"))),
)

///|
pub(all) struct Transition {
  id : String
  fromId : String
  toId : String
  duration : Double
  tracks : Map[String, Track]
} derive(FromJson, ToJson)

///|
pub(all) struct AudioTrack {
  id : String
  name : String
  asset : MediaAsset
  volume : Double
  muted : Bool
  start : Double
  offset : Double
  duration : Double
} derive(FromJson, ToJson)

///|
pub(all) struct Scene {
  id : String
  name : String
  width : Double
  height : Double
  background : String
  objects : Map[String, SceneObject]
  compositionOrder : Array[String]
  compositions : Map[String, Composition]
  transitions : Map[String, Transition]
  audioTracks : Map[String, AudioTrack]?
  deleted : Bool?
} derive(FromJson, ToJson)

///|
pub(all) struct Project {
  version : Int
  name : String
  sceneOrder : Array[String]
  scenes : Map[String, Scene]
} derive(FromJson, ToJson)

///|
pub(all) struct Segment {
  kind : String
  id : String
  start : Double
  duration : Double
} derive(ToJson)

///|
pub(all) struct RenderObject {
  object : SceneObject
  state : ObjectState
  writeProgress : Double
  order : String
  videoTimeMs : Double?
} derive(ToJson)

///|
pub(all) struct Frame {
  objects : Array[RenderObject]
  background : String
  width : Double
  height : Double
} derive(ToJson)
