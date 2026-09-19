///|
pub fn text_markup(
  item : Drawable,
  prefix : String,
  measure : (String, Double) -> TextMetrics,
  glyph_opacity? : (Int) -> Double,
) -> String {
  let s = item.state
  let size = finite(s.fontSize).max(0.0)
  let progress = unit(item.progress)
  let lines = s.text.split("\n").map(fn(line) { line.to_owned() }).to_array()
  let metrics = measure(s.text, size)
  let opacity = match glyph_opacity {
    Some(f) => Some(f)
    None if item.order == Sequential && progress < 1.0 => {
      let count = s.text.iter().filter(fn(c) { c != '\n' }).count().to_double()
      Some(fn(index) { unit(progress * count - index.to_double()) })
    }
    None => None
  }
  let mut index = 0
  let body = StringBuilder()
  for line_index, line in lines {
    let y = (line_index.to_double() - (lines.length() - 1).to_double() / 2.0) *
      metrics.line_height +
      metrics.baseline
    body.write_string(
      "<text x=\"0\" y=\"\{number(y)}\" text-anchor=\"middle\" xml:space=\"preserve\">",
    )
    match opacity {
      None => body.write_string(escape_xml(line))
      Some(opacity) =>
        for character in line {
          body.write_string(
            "<tspan opacity=\"\{number(opacity(index))}\">\{escape_xml(character.to_string())}</tspan>",
          )
          index += 1
        }
    }
    body.write_string("</text>")
  }
  let font = "text-rendering=\"geometricPrecision\" font-family=\"\{escape_xml("'Poietra Inter', 'Poietra Noto Sans JP', sans-serif")}\" font-size=\"\{number(size)}\""
  if item.order == Sequential || progress >= 1.0 {
    return "<g \{font}>\{body.to_string()}</g>"
  }
  let padding = size * 0.2
  "<defs><clipPath id=\"\{prefix}-text\"><rect x=\"\{number(-metrics.width / 2.0)}\" y=\"\{number(-metrics.height / 2.0 - padding)}\" width=\"\{number(metrics.width * progress)}\" height=\"\{number(metrics.height + padding * 2.0)}\"/></clipPath></defs><g clip-path=\"url(#\{prefix}-text)\" \{font}>\{body.to_string()}</g>"
}

///|
pub fn equation_glyph_progress(
  progress : Double,
  order : WriteOrder,
  glyphs : Int,
  index : Int,
) -> Double {
  if order == Sequential {
    unit(progress * glyphs.to_double() - index.to_double())
  } else {
    unit(progress)
  }
}

///|
pub fn equation_fill_progress(progress : Double) -> Double {
  unit((progress - 0.55) / (1.0 - 0.55))
}

///|
pub fn equation_markup(
  equation : Equation,
  progress : Double,
  order : WriteOrder,
) -> String {
  let output = StringBuilder()
  let mut index = 0
  fn attributes(node : MathNode) -> Unit {
    for (key, value) in node.attributes {
      output.write_string(" \{key}=\"\{escape_xml(value)}\"")
    }
  }
  fn render(node : MathNode) -> Unit {
    let tag = math_tag_name(node.tag)
    if node.tag == Group {
      output.write_string("<g")
      attributes(node)
      output.write_string(">")
      for child in node.children {
        render(child)
      }
      output.write_string("</g>")
      return
    }
    let glyph_progress = equation_glyph_progress(
      progress,
      order,
      equation.glyphs,
      index,
    )
    index += 1
    if glyph_progress == 0.0 {
      return
    }
    if glyph_progress == 1.0 {
      output.write_string("<\{tag}")
      attributes(node)
      output.write_string("/>")
      return
    }
    output.write_string(
      "<g fill-opacity=\"\{number(equation_fill_progress(glyph_progress))}\" stroke=\"currentColor\" stroke-width=\"18\" stroke-linecap=\"round\" stroke-linejoin=\"round\"><\{tag}",
    )
    attributes(node)
    output.write_string(
      " pathLength=\"1\" stroke-dasharray=\"1\" stroke-dashoffset=\"\{number(1.0 - glyph_progress)}\"/></g>",
    )
  }
  render(equation.tree)
  output.to_string()
}
