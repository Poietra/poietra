///|
pub(all) enum WriteOrder {
  Together
  Sequential
} derive(Eq)

///|
pub(all) struct Drawable {
  id : String
  kind : @scene.ObjectKind
  state : @scene.ObjectState
  world : @scene.Affine?
  progress : Double
  order : WriteOrder
  image : String?
  video_frame : String?
} derive(Eq)

///|
pub(all) struct Bounds {
  x : Double
  y : Double
  width : Double
  height : Double
}

///|
pub(all) struct TextMetrics {
  width : Double
  height : Double
  line_height : Double
  baseline : Double
}

///|
pub(all) struct MathNode {
  tag : MathTag
  attributes : Array[(String, String)]
  children : Array[MathNode]
}

///|
pub(all) enum MathTag {
  Group
  Path
  Rectangle
  Line
  Polygon
  Polyline
  Circle
  Ellipse
} derive(Eq)

///|
pub fn math_tag(value : String) -> MathTag? {
  match value {
    "g" => Some(Group)
    "path" => Some(Path)
    "rect" => Some(Rectangle)
    "line" => Some(Line)
    "polygon" => Some(Polygon)
    "polyline" => Some(Polyline)
    "circle" => Some(Circle)
    "ellipse" => Some(Ellipse)
    _ => None
  }
}

///|
pub fn math_tag_name(value : MathTag) -> String {
  match value {
    Group => "g"
    Path => "path"
    Rectangle => "rect"
    Line => "line"
    Polygon => "polygon"
    Polyline => "polyline"
    Circle => "circle"
    Ellipse => "ellipse"
  }
}

///|
pub(all) struct Equation {
  width : Double
  height : Double
  x : Double
  y : Double
  tree : MathNode
  glyphs : Int
}

///|
pub(all) struct Resources {
  equation : (String) -> Equation?
  measure_text : (String, Double) -> TextMetrics
  image : (String?) -> String?
  font_styles : (Array[String]) -> String
}

///|
pub(all) struct RenderFrame {
  width : Double
  height : Double
  background : String
  objects : Array[Drawable]
}

///|
/// One representation feeds both serialized SVG and the retained browser view.
pub(all) struct SvgObject {
  id : String
  transform : String
  opacity : String
  fill : String
  color : String
  stroke : String
  stroke_width : String
  filter : String?
  definitions : String
  body : String
}

///|
pub(all) struct SvgFrame {
  width : String
  height : String
  fonts : String
  background : String?
  objects : Array[SvgObject]
}
