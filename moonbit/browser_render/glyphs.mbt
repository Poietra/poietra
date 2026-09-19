///|
priv struct GlyphPaint {
  fill : Bool
  stroke : Bool
  stroke_width : Double?
}

///|
priv struct GlyphGeometry {
  path : CanvasPath
  length : Double
  rectangle : @render.Bounds?
}

///|
priv struct Glyph {
  geometry : GlyphGeometry
  transform : CanvasMatrix
  complete : GlyphPaint
  writing : GlyphPaint
}

///|
fn attribute(node : @render.MathNode, name : String) -> String? {
  node.attributes
  .iter()
  .find_first(fn(pair) { pair.0 == name })
  .map(fn(pair) { pair.1 })
}

///|
fn numeric_attribute(
  node : @render.MathNode,
  name : String,
  fallback : Double,
) -> Double {
  guard attribute(node, name) is Some(source) else { return fallback }
  let number = numeric_string(source)
  if @editor.trim_text(source).is_empty() || number.is_nan() || number.is_inf() {
    return unsupported("Unsupported equation geometry.")
  }
  number
}

///|
fn node_paint(node : @render.MathNode, inherited : GlyphPaint) -> GlyphPaint {
  let fill = attribute(node, "fill")
  let stroke = attribute(node, "stroke")
  for paint in [fill, stroke] {
    if paint is Some(value) && value != "none" && value != "currentColor" {
      return unsupported("Unsupported equation paint.")
    }
  }
  let stroke_width = if attribute(node, "stroke-width") is Some(_) {
    Some(numeric_attribute(node, "stroke-width", 0.0))
  } else {
    inherited.stroke_width
  }
  if stroke_width is Some(width) && width < 0.0 {
    return unsupported("Unsupported equation stroke.")
  }
  {
    fill: fill.map(fn(value) { value != "none" }).unwrap_or(inherited.fill),
    stroke: stroke
    .map(fn(value) { value != "none" })
    .unwrap_or(inherited.stroke),
    stroke_width,
  }
}

///|
fn node_transform(
  node : @render.MathNode,
  parent : CanvasMatrix,
) -> CanvasMatrix {
  guard attribute(node, "transform") is Some(source) && !source.is_empty() else {
    return parent
  }
  let group = svg_element("g")
  group._call("setAttribute", [@core.any("transform"), @core.any(source)])
  |> ignore
  let consolidated = group
    ._get("transform")
    ._get("baseVal")
    ._call("consolidate", [])
  if @core.is_nullish(consolidated) {
    return unsupported("Unsupported equation transform.")
  }
  let result = @core.any(parent)._call("multiply", [consolidated._get("matrix")])
  for field in ["a", "b", "c", "d", "e", "f"] {
    let value : Double = result._get(field).cast()
    if value.is_nan() || value.is_inf() {
      return unsupported("Unsupported equation transform.")
    }
  }
  result.cast()
}

///|
fn glyph_geometry(node : @render.MathNode) -> GlyphGeometry {
  match node.tag {
    Path => {
      guard attribute(node, "d") is Some(data) && !data.is_empty() else {
        return unsupported("Unsupported equation glyph.")
      }
      let path = canvas_path(data)
      let length = path_length(data)
      if length <= 0.0 {
        return unsupported("Unsupported equation path length.")
      }
      { path, length, rectangle: None, }
    }
    Rectangle => {
      let x = numeric_attribute(node, "x", 0.0)
      let y = numeric_attribute(node, "y", 0.0)
      let width = numeric_attribute(node, "width", 0.0)
      let height = numeric_attribute(node, "height", 0.0)
      if width <= 0.0 ||
        height <= 0.0 ||
        numeric_attribute(node, "rx", 0.0) != 0.0 ||
        numeric_attribute(node, "ry", 0.0) != 0.0 {
        return unsupported("Unsupported equation rectangle.")
      }
      let path = canvas_path("")
      path_rect(path, x, y, width, height)
      {
        path,
        length: 2.0 * (width + height),
        rectangle: Some({ x, y, width, height, }),
      }
    }
    _ => unsupported("Unsupported equation glyph.")
  }
}

///|
fn parse_math_node(value : @core.Any) -> @render.MathNode {
  guard @render.math_tag(value._get("tag").cast()) is Some(tag) else {
    return unsupported("Unsupported equation glyph.")
  }
  let attributes = value._get("attributes")
  let children : FixedArray[@core.Any] = value._get("children").cast()
  {
    tag,
    attributes: @core.object_keys(attributes).map(fn(key) {
      (key, attributes._get(key).cast())
    }),
    children: Array::makei(children.length(), fn(i) {
      parse_math_node(children[i])
    }),
  }
}

///|
fn paint_glyphs(
  context : @canvas.CanvasRenderingContext2D,
  glyphs : Array[Glyph],
  progress : Double,
  order : @render.WriteOrder,
  color : String,
) -> Unit {
  saved_canvas(context, fn() {
    context.fillStyle = "#000000"
    context.strokeStyle = "#000000"
    context.fillStyle = color
    context.strokeStyle = color
    round_caps(context)
    let opacity = context.globalAlpha
    for index, glyph in glyphs {
      let amount = @render.equation_glyph_progress(
        progress,
        order,
        glyphs.length(),
        index,
      )
      if amount == 0.0 {
        continue
      }
      let writing = amount < 1.0
      let paint = if writing { glyph.writing } else { glyph.complete }
      let fill_opacity = if writing {
        @render.equation_fill_progress(amount)
      } else {
        1.0
      }
      saved_canvas(context, fn() {
        apply_matrix(context, glyph.transform)
        if paint.fill && fill_opacity > 0.0 {
          context.globalAlpha = opacity * fill_opacity
          match glyph.geometry.rectangle {
            Some(rect) =>
              context.fillRect(rect.x, rect.y, rect.width, rect.height)
            None => fill_path(context, glyph.geometry.path)
          }
        }
        if paint.stroke && paint.stroke_width is Some(width) && width > 0.0 {
          context.globalAlpha = opacity
          context.lineWidth = width
          canvas_dash(
            context,
            if writing {
              [glyph.geometry.length, glyph.geometry.length]
            } else {
              []
            },
            if writing {
              (1.0 - amount) * glyph.geometry.length
            } else {
              0.0
            },
          )
          stroke_path(context, glyph.geometry.path)
        }
      })
    }
  })
}

///|
pub fn prepare_equation_drawing(equation : @core.Any) -> @core.Any {
  if !canvas_available() ||
    @core.is_undefined(@core.global_this()._get("DOMMatrix")) {
    return @core.null()
  }
  let count : Int = equation._get("glyphs").cast()
  if count <= 0 || count > 2048 {
    return @core.null()
  }
  @core.throwable(fn() {
    let source_bytes = @core.json_stringify(equation._get("tree")).length() * 2
    if source_bytes > 1024 * 1024 {
      return @core.null()
    }
    let cached = equation_models._call("get", [equation])
    let tree = if @core.is_undefined(cached) {
      parse_math_node(equation._get("tree"))
    } else {
      let cached : @render.Equation = cached.cast()
      cached.tree
    }
    let glyphs : Array[Glyph] = []
    let paths : Map[String, GlyphGeometry] = Map([])
    fn visit(
      node : @render.MathNode,
      parent : CanvasMatrix,
      inherited : GlyphPaint,
    ) -> Unit {
      let transform = node_transform(node, parent)
      let complete = node_paint(node, inherited)
      if node.tag == @render.Group {
        for child in node.children {
          visit(child, transform, complete)
        }
        return
      }
      if !node.children.is_empty() {
        unsupported("Unsupported equation glyph children.")
      }
      if complete.stroke && complete.stroke_width is None {
        unsupported("Inherited equation stroke width.")
      }
      let data = if node.tag == @render.Path {
        attribute(node, "d")
      } else {
        None
      }
      let geometry = match data.bind(fn(data) { paths.get(data) }) {
        Some(geometry) => geometry
        None => glyph_geometry(node)
      }
      if data is Some(data) && !data.is_empty() {
        paths[data] = geometry
      }
      let writing = node_paint(node, {
        ..inherited,
        stroke: true,
        stroke_width: Some(18.0),
      })
      glyphs.push({ geometry, transform, complete, writing, })
    }
    visit(tree, canvas_matrix(), {
      fill: true,
      stroke: false,
      stroke_width: None,
    })
    if glyphs.length() != count {
      return @core.null()
    }
    @core.from_entries([
      ("sourceBytes", @core.any(source_bytes)),
      ("glyphCount", @core.any(glyphs.length())),
      (
        "paint",
        @core.any(fn(
          context : @core.Any,
          progress : Double,
          order : String,
          color : String,
        ) {
          paint_glyphs(
            context.cast(),
            glyphs,
            progress,
            if order == "sequential" {
              @render.Sequential
            } else {
              @render.Together
            },
            color,
          )
        }),
      ),
    ])
  }) catch {
    _ => @core.null()
  }
}
