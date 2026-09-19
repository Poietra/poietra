///|
/// The saved document uses strings; executable data has a closed set of kinds.
pub(all) enum ObjectKind {
  Circle
  Rectangle
  Text
  Equation
  Path
  Arrow
  NumberLine
  Image
  Video
} derive(Eq)

///|
pub(all) enum AnimationKind {
  Move
  Write
  Fade
  Grow
  Cut
} derive(Eq)

///|
pub(all) enum Effect {
  Normal
  Glow
} derive(Eq)

///|
pub fn object_kind(value : String) -> ObjectKind? {
  match value {
    "circle" => Some(Circle)
    "rectangle" => Some(Rectangle)
    "text" => Some(Text)
    "equation" => Some(Equation)
    "path" => Some(Path)
    "arrow" => Some(Arrow)
    "numberline" => Some(NumberLine)
    "image" => Some(Image)
    "video" => Some(Video)
    _ => None
  }
}

///|
pub fn object_kind_name(kind : ObjectKind) -> String {
  match kind {
    Circle => "circle"
    Rectangle => "rectangle"
    Text => "text"
    Equation => "equation"
    Path => "path"
    Arrow => "arrow"
    NumberLine => "numberline"
    Image => "image"
    Video => "video"
  }
}

///|
pub fn animation_kind(value : String) -> AnimationKind? {
  match value {
    "move" => Some(Move)
    "write" => Some(Write)
    "fade" => Some(Fade)
    "grow" => Some(Grow)
    "none" => Some(Cut)
    _ => None
  }
}

///|
pub fn effect_kind(value : String) -> Effect? {
  match value {
    "none" => Some(Normal)
    "glow" => Some(Glow)
    _ => None
  }
}

///|
pub fn effect_name(value : Effect) -> String {
  match value {
    Normal => "none"
    Glow => "glow"
  }
}

///|
pub fn animation_name(value : AnimationKind) -> String {
  match value {
    Move => "move"
    Write => "write"
    Fade => "fade"
    Grow => "grow"
    Cut => "none"
  }
}

///|
pub impl ToJson for ObjectKind with fn to_json(self) {
  match self {
    Circle => "circle"
    Rectangle => "rectangle"
    Text => "text"
    Equation => "equation"
    Path => "path"
    Arrow => "arrow"
    NumberLine => "numberline"
    Image => "image"
    Video => "video"
  }
}

///|
pub impl @json.FromJson for ObjectKind with fn from_json(value, path) {
  let text : String = @json.from_json(value, path~)
  match object_kind(text) {
    Some(kind) => kind
    None => raise @json.JsonDecodeError((path, "Unknown object kind"))
  }
}

///|
pub impl ToJson for AnimationKind with fn to_json(self) {
  match self {
    Move => "move"
    Write => "write"
    Fade => "fade"
    Grow => "grow"
    Cut => "none"
  }
}

///|
pub impl @json.FromJson for AnimationKind with fn from_json(value, path) {
  let text : String = @json.from_json(value, path~)
  match animation_kind(text) {
    Some(kind) => kind
    None => raise @json.JsonDecodeError((path, "Unknown animation kind"))
  }
}

///|
pub impl ToJson for Effect with fn to_json(self) {
  effect_name(self).to_json()
}

///|
pub impl @json.FromJson for Effect with fn from_json(value, path) {
  let text : String = @json.from_json(value, path~)
  match effect_kind(text) {
    Some(kind) => kind
    None => raise @json.JsonDecodeError((path, "Unknown effect kind"))
  }
}

///|
pub(all) enum CurveProperty {
  PositionX
  PositionY
  ObjectWidth
  ObjectHeight
  ObjectRotation
  ObjectOpacity
  ObjectFill
  ObjectStroke
  ObjectStrokeWidth
  ObjectFontSize
  ObjectCornerRadius
  Control1X
  Control1Y
  Control2X
  Control2Y
  ObjectReveal
  ObjectAnchorX
  ObjectAnchorY
  ObjectScaleX
  ObjectScaleY
  ObjectShear
} derive(Eq)

///|
pub fn curve_property(value : String) -> CurveProperty? {
  match value {
    "x" => Some(PositionX)
    "y" => Some(PositionY)
    "width" => Some(ObjectWidth)
    "height" => Some(ObjectHeight)
    "rotation" => Some(ObjectRotation)
    "opacity" => Some(ObjectOpacity)
    "fill" => Some(ObjectFill)
    "stroke" => Some(ObjectStroke)
    "strokeWidth" => Some(ObjectStrokeWidth)
    "fontSize" => Some(ObjectFontSize)
    "cornerRadius" => Some(ObjectCornerRadius)
    "c1x" => Some(Control1X)
    "c1y" => Some(Control1Y)
    "c2x" => Some(Control2X)
    "c2y" => Some(Control2Y)
    "reveal" => Some(ObjectReveal)
    "anchorX" => Some(ObjectAnchorX)
    "anchorY" => Some(ObjectAnchorY)
    "scaleX" => Some(ObjectScaleX)
    "scaleY" => Some(ObjectScaleY)
    "shear" => Some(ObjectShear)
    _ => None
  }
}

///|
pub fn curve_property_name(value : CurveProperty) -> String {
  match value {
    PositionX => "x"
    PositionY => "y"
    ObjectWidth => "width"
    ObjectHeight => "height"
    ObjectRotation => "rotation"
    ObjectOpacity => "opacity"
    ObjectFill => "fill"
    ObjectStroke => "stroke"
    ObjectStrokeWidth => "strokeWidth"
    ObjectFontSize => "fontSize"
    ObjectCornerRadius => "cornerRadius"
    Control1X => "c1x"
    Control1Y => "c1y"
    Control2X => "c2x"
    Control2Y => "c2y"
    ObjectReveal => "reveal"
    ObjectAnchorX => "anchorX"
    ObjectAnchorY => "anchorY"
    ObjectScaleX => "scaleX"
    ObjectScaleY => "scaleY"
    ObjectShear => "shear"
  }
}

///|
pub impl @json.FromJson for CurveProperty with fn from_json(json, path) {
  if json is String(name) && curve_property(name) is Some(property) {
    property
  } else {
    raise @json.JsonDecodeError((path, "Invalid curve property"))
  }
}

///|
pub impl ToJson for CurveProperty with fn to_json(self) {
  curve_property_name(self).to_json()
}

///|
pub(all) enum CurveValue {
  CurveNumber(Double)
  CurveColor(String)
} derive(Eq)

///|
pub impl @json.FromJson for CurveValue with fn from_json(json, path) {
  match json {
    Number(value, ..) => CurveNumber(value)
    String(value) => CurveColor(value)
    _ => raise @json.JsonDecodeError((path, "Invalid curve value"))
  }
}

///|
pub impl ToJson for CurveValue with fn to_json(self) {
  match self {
    CurveNumber(value) => value.to_json()
    CurveColor(value) => value.to_json()
  }
}
