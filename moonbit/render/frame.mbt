///|
fn shape_markup(
  item : Drawable,
  prefix : String,
  resources : Resources,
  video_hits : Bool,
) -> String {
  let s = item.state
  let progress = unit(item.progress)
  let draw = if progress < 1.0 {
    " pathLength=\"1\" stroke-dasharray=\"1\" stroke-dashoffset=\"\{number(1.0 - progress)}\""
  } else {
    ""
  }
  match item.kind {
    Text => return text_markup(item, prefix, resources.measure_text)
    Image | Video => {
      let source = if item.kind == @scene.Video {
        item.video_frame
      } else {
        (resources.image)(item.image)
      }
      let width = finite(s.width).abs()
      let height = finite(s.height).abs()
      let x = -width / 2.0
      let y = -height / 2.0
      let radius = finite(s.cornerRadius)
        .min(width / 2.0)
        .min(height / 2.0)
        .max(0.0)
      guard source is Some(source) && !source.is_empty() else {
        // The invisible SVG over a painted canvas still needs a selectable shape.
        return if video_hits && item.kind == @scene.Video {
          "<rect x=\"\{number(x)}\" y=\"\{number(y)}\" width=\"\{number(width)}\" height=\"\{number(height)}\" rx=\"\{number(radius)}\" fill=\"transparent\" stroke=\"none\"/>"
        } else {
          ""
        }
      }
      return "<defs><clipPath id=\"\{prefix}-image\"><rect x=\"\{number(x)}\" y=\"\{number(y)}\" width=\"\{number(width)}\" height=\"\{number(height)}\" rx=\"\{number(radius)}\"/></clipPath><clipPath id=\"\{prefix}-reveal\"><rect x=\"\{number(x)}\" y=\"\{number(y)}\" width=\"\{number(width * progress)}\" height=\"\{number(height)}\"/></clipPath></defs><g clip-path=\"url(#\{prefix}-reveal)\"><image href=\"\{escape_xml(source)}\" x=\"\{number(x)}\" y=\"\{number(y)}\" width=\"\{number(width)}\" height=\"\{number(height)}\" preserveAspectRatio=\"none\" clip-path=\"url(#\{prefix}-image)\"/><rect x=\"\{number(x)}\" y=\"\{number(y)}\" width=\"\{number(width)}\" height=\"\{number(height)}\" rx=\"\{number(radius)}\" fill=\"none\"/></g>"
    }
    Equation => {
      guard (resources.equation)(s.text) is Some(equation) else {
        return text_markup(item, prefix, resources.measure_text)
      }
      let scale = finite(s.fontSize).max(0.0) / 1000.0
      return "<g transform=\"scale(\{number(scale)}) translate(\{number(-equation.x - equation.width / 2.0)} \{number(-equation.y - equation.height / 2.0)})\" fill=\"currentColor\" stroke=\"none\">\{equation_markup(equation, progress, item.order)}</g>"
    }
    _ => ()
  }
  match shape_geometry(item.kind, s) {
    None => ""
    Some(Ellipse(x, y)) =>
      "<ellipse cx=\"0\" cy=\"0\" rx=\"\{number(x)}\" ry=\"\{number(y)}\" fill-opacity=\"\{number(progress)}\"\{draw}/>"
    Some(Rectangle(width, height, radius)) =>
      "<rect x=\"\{number(-width / 2.0)}\" y=\"\{number(-height / 2.0)}\" width=\"\{number(width)}\" height=\"\{number(height)}\" rx=\"\{number(radius)}\" fill-opacity=\"\{number(progress)}\"\{draw}/>"
    Some(Path(path)) => "<path d=\"\{path}\" fill=\"none\"\{draw}/>"
    Some(Arrow(geometry) | NumberLine(geometry)) => {
      let ticks = StringBuilder()
      if item.kind == @scene.NumberLine {
        for index = 0; index < 11; index = index + 1 {
          ticks.write_string(
            "<path d=\"\{numberline_tick_path(geometry.length, index)}\" opacity=\"\{number(numberline_tick_progress(progress, index))}\"/>",
          )
        }
      }
      "<g transform=\"rotate(\{number(geometry.angle)})\" fill=\"none\"><path d=\"M0 0 H\{number(geometry.length)}\"\{draw}/>\{ticks.to_string()}<path d=\"\{arrow_head_path(geometry)}\" opacity=\"\{number(arrow_head_progress(progress))}\"/></g>"
    }
  }
}

///|
/// The caller supplies prepared resources; this stage has no DOM, I/O or global clock.
pub fn frame_to_svg(
  frame : RenderFrame,
  prefix : String,
  background : Bool,
  resources : Resources,
  video_hits? : Bool = false,
) -> String {
  let prefix = "poietra-" + safe_id(prefix)
  let width = finite(frame.width, fallback=1280.0).max(1.0)
  let height = finite(frame.height, fallback=720.0).max(1.0)
  let objects = StringBuilder()
  let sources = []
  for index, item in frame.objects {
    if item.kind == @scene.Text ||
      (
        item.kind == @scene.Equation &&
        (resources.equation)(item.state.text) is None
      ) {
      sources.push(item.state.text)
    }
    if !item.state.visible ||
      unit(item.state.opacity) == 0.0 ||
      unit(item.progress) == 0.0 {
      continue
    }
    let s = item.state
    let id = "\{prefix}-\{index}"
    let glow = s.effect == @scene.Glow
    if glow {
      let bounds = object_bounds(item, resources)
      objects.write_string(
        "<defs><filter id=\"\{id}-glow\" filterUnits=\"userSpaceOnUse\" x=\"\{number(bounds.x - s.x - 16.0)}\" y=\"\{number(bounds.y - s.y - 16.0)}\" width=\"\{number(bounds.width + 32.0)}\" height=\"\{number(bounds.height + 32.0)}\" color-interpolation-filters=\"sRGB\"><feGaussianBlur stdDeviation=\"4\"/><feMerge><feMergeNode/><feMergeNode in=\"SourceGraphic\"/></feMerge></filter></defs>",
      )
    }
    objects.write_string(
      "<g data-object-id=\"\{escape_xml(item.id)}\" transform=\"\{drawable_transform(item)}\" opacity=\"\{number(unit(s.opacity))}\" fill=\"\{escape_xml(color(s.fill))}\" color=\"\{escape_xml(color(s.fill, fallback="#d7d8e4"))}\" stroke=\"\{escape_xml(color(s.stroke))}\" stroke-width=\"\{number(finite(s.strokeWidth).max(0.0))}\" stroke-linecap=\"round\" stroke-linejoin=\"round\"",
    )
    if glow {
      objects.write_string(" filter=\"url(#\{id}-glow)\"")
    }
    objects.write_string(">")
    objects.write_string(shape_markup(item, id, resources, video_hits))
    objects.write_string("</g>")
  }
  let output = StringBuilder()
  output.write_string(
    "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"\{number(width)}\" height=\"\{number(height)}\" viewBox=\"0 0 \{number(width)} \{number(height)}\">",
  )
  output.write_string((resources.font_styles)(sources))
  if background {
    output.write_string(
      "<rect width=\"\{number(width)}\" height=\"\{number(height)}\" fill=\"\{escape_xml(color(frame.background, fallback="#08090b"))}\"/>",
    )
  }
  output.write_string(objects.to_string())
  output.write_string("</svg>")
  output.to_string()
}

///|
pub fn affine_transform(matrix : @scene.Affine) -> String {
  "matrix(\{number(matrix.a)} \{number(matrix.b)} \{number(matrix.c)} \{number(matrix.d)} \{number(matrix.e)} \{number(matrix.f)})"
}

///|
pub fn drawable_transform(item : Drawable) -> String {
  match item.world {
    Some(matrix) => affine_transform(matrix)
    None =>
      if item.state.has_transform() {
        affine_transform(item.state.local_matrix())
      } else {
        "translate(\{number(item.state.x)} \{number(item.state.y)}) rotate(\{number(item.state.rotation)})"
      }
  }
}
