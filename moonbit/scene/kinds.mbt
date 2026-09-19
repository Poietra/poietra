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
