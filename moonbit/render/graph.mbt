///|
pub(all) struct GraphLabel {
  x : Double
  y : Double
  text : String
} derive(Eq)

///|
pub(all) struct GraphGeometry {
  curve : String
  axes : String
  grid : String
  labels : Array[GraphLabel]
  limited : Bool
} derive(Eq)

///|
priv struct PreparedGraph {
  definition : @scene.GraphDefinition
  width : Double
  height : Double
  plot : @math_plot.Plot
  full_curve : String
  axes : String
  grid : String
  labels : Array[GraphLabel]
}

///|
// Cache ownership stays at the rendering boundary; the numeric package is pure.
// Each source retains only its last geometry, bounded independently of documents.
let graph_programs : Map[String, @math_plot.Program?] = Map([])

///|
let prepared_graphs : Map[String, PreparedGraph] = Map([])

///|
let graph_sources : Array[String] = []

///|
fn graph_program(source : String, syntax : Int) -> @math_plot.Program? {
  let key = "\{syntax}:\{source}"
  if graph_programs.get(key) is Some(program) {
    return program
  }
  if graph_sources.length() >= 64 {
    let oldest = graph_sources.remove(0)
    graph_programs.remove(oldest)
    prepared_graphs.remove(oldest)
  }
  let program = Some(@math_plot.prepare_graph(source, syntax)) catch {
    _ => None
  }
  graph_sources.push(key)
  graph_programs[key] = program
  program
}

///|
fn tick_step(range : Double) -> Double {
  let power = @math.pow(10.0, @math.log10(range / 8.0).floor())
  let fraction = range / 8.0 / power
  power *
  (if fraction <= 1.0 {
    1.0
  } else if fraction <= 2.0 {
    2.0
  } else if fraction <= 5.0 {
    5.0
  } else {
    10.0
  })
}

///|
fn tick_label(value : Double) -> String {
  if value == 0.0 {
    "0"
  } else if value.abs() < 0.001 {
    value.to_string()
  } else {
    number(value)
  }
}

///|
fn prepare_graph(
  definition : @scene.GraphDefinition,
  width : Double,
  height : Double,
) -> PreparedGraph {
  let viewport : @math_plot.Viewport = {
    x_min: definition.xMin,
    x_max: definition.xMax,
    y_min: definition.yMin,
    y_max: definition.yMax,
    width,
    height,
  }
  let plot = match
    graph_program(definition.expression, definition.syntaxVersion) {
    Some(program) =>
      (if program.is_implicit() {
        @math_plot.plot_implicit
      } else {
        @math_plot.plot
      })(
        program,
        viewport,
        definition.a,
        definition.b,
        definition.c,
        definition.breaks,
      )
    None => @math_plot.Plot::{ segments: [], limited: false, evaluations: 0, }
  }
  let axes = StringBuilder()
  let grid = StringBuilder()
  let labels : Array[GraphLabel] = []
  let origin = viewport.point(0.0, 0.0)
  if definition.axes {
    if definition.xMin <= 0.0 && definition.xMax >= 0.0 {
      axes.write_string(
        "M\{number(origin.0)} \{number(-height / 2.0)} V\{number(height / 2.0)}",
      )
    }
    if definition.yMin <= 0.0 && definition.yMax >= 0.0 {
      axes.write_string(
        "M\{number(-width / 2.0)} \{number(origin.1)} H\{number(width / 2.0)}",
      )
    }
  }
  let x_step = tick_step(definition.xMax - definition.xMin)
  let y_step = tick_step(definition.yMax - definition.yMin)
  for i = 0; i < 24; i = i + 1 {
    let x = ((definition.xMin / x_step).ceil() + i.to_double()) * x_step
    if x > definition.xMax {
      break
    }
    let at = viewport.point(x, 0.0).0
    if definition.grid {
      grid.write_string(
        "M\{number(at)} \{number(-height / 2.0)} V\{number(height / 2.0)}",
      )
    }
    if definition.axes && at > -width / 2.0 + 16.0 && at < width / 2.0 - 28.0 {
      let y = origin.1.max(-height / 2.0 + 4.0).min(height / 2.0 - 18.0)
      axes.write_string("M\{number(at)} \{number(y - 3.0)} V\{number(y + 3.0)}")
      labels.push({ x: at + 4.0, y: y + 15.0, text: tick_label(x), })
    }
  }
  for i = 0; i < 24; i = i + 1 {
    let y = ((definition.yMin / y_step).ceil() + i.to_double()) * y_step
    if y > definition.yMax {
      break
    }
    let at = viewport.point(0.0, y).1
    if definition.grid {
      grid.write_string(
        "M\{number(-width / 2.0)} \{number(at)} H\{number(width / 2.0)}",
      )
    }
    if definition.axes &&
      y != 0.0 &&
      at > -height / 2.0 + 12.0 &&
      at < height / 2.0 - 8.0 {
      let x = origin.0.max(-width / 2.0 + 3.0).min(width / 2.0 - 38.0)
      axes.write_string("M\{number(x - 3.0)} \{number(at)} H\{number(x + 3.0)}")
      labels.push({ x: x + 6.0, y: at - 5.0, text: tick_label(y), })
    }
  }
  {
    definition: { ..definition, breaks: definition.breaks.copy(), },
    width,
    height,
    plot,
    full_curve: graph_curve(plot.segments, 1.0),
    axes: axes.to_string(),
    grid: grid.to_string(),
    labels,
  }
}

///|
fn graph_curve(
  segments : Array[@math_plot.Segment],
  progress : Double,
) -> String {
  let lengths = segments.map(fn(s) { @math.hypot(s.x1 - s.x0, s.y1 - s.y0) })
  let mut remaining = lengths.fold(init=0.0, fn(sum, length) { sum + length }) *
    unit(progress)
  let path = StringBuilder()
  let mut previous : (Double, Double)? = None
  for index, segment in segments {
    if remaining <= 0.0 {
      break
    }
    let length = lengths[index]
    let amount = if length == 0.0 { 1.0 } else { (remaining / length).min(1.0) }
    if previous != Some((segment.x0, segment.y0)) {
      path.write_string("M\{number(segment.x0)} \{number(segment.y0)}")
    }
    let x = segment.x0 + amount * (segment.x1 - segment.x0)
    let y = segment.y0 + amount * (segment.y1 - segment.y0)
    path.write_string("L\{number(x)} \{number(y)}")
    previous = Some((x, y))
    remaining -= length
  }
  path.to_string()
}

///|
pub fn graph_geometry(
  state : @scene.ObjectState,
  progress : Double,
) -> GraphGeometry {
  let definition = state.graph.unwrap_or(@scene.default_graph())
  let width = finite(state.width).abs()
  let height = finite(state.height).abs()
  if width == 0.0 ||
    height == 0.0 ||
    @scene.graph_value_error(definition) is Some(_) {
    return { curve: "", axes: "", grid: "", labels: [], limited: false, }
  }
  let key = "\{definition.syntaxVersion}:\{definition.expression}"
  let cached = prepared_graphs.get(key)
  let prepared = match cached {
    Some(value) if value.definition == definition &&
      value.width == width &&
      value.height == height => value
    _ => {
      let value = prepare_graph(definition, width, height)
      prepared_graphs[key] = value
      value
    }
  }
  {
    curve: if unit(progress) == 1.0 {
      prepared.full_curve
    } else {
      graph_curve(prepared.plot.segments, progress)
    },
    axes: prepared.axes,
    grid: prepared.grid,
    labels: prepared.labels.copy(),
    limited: prepared.plot.limited,
  }
}

///|
fn graph_markup(
  graph : GraphGeometry,
  state : @scene.ObjectState,
  progress : Double,
) -> String {
  let labels = StringBuilder()
  for label in graph.labels {
    labels.write_string(
      "<text x=\"\{number(label.x)}\" y=\"\{number(label.y)}\" stroke=\"none\">\{escape_xml(label.text)}</text>",
    )
  }
  "<g fill=\"none\" stroke=\"\{color(state.fill)}\" stroke-width=\"1\"><path data-graph-grid=\"true\" d=\"\{graph.grid}\" opacity=\"\{number(progress * 0.15)}\"/><path data-graph-axes=\"true\" d=\"\{graph.axes}\" opacity=\"\{number(progress * 0.65)}\"/></g><g fill=\"\{color(state.fill)}\" font-family=\"sans-serif\" font-size=\"12\" opacity=\"\{number(progress * 0.75)}\">\{labels.to_string()}</g><path data-graph-curve=\"true\" d=\"\{graph.curve}\" fill=\"none\"/>"
}
