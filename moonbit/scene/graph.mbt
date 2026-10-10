///|
pub fn default_graph() -> GraphDefinition {
  {
    syntaxVersion: 1,
    expression: "x^3 - a*x",
    xMin: -3.0,
    xMax: 3.0,
    yMin: -4.0,
    yMax: 4.0,
    a: 3.0,
    b: 0.0,
    c: 0.0,
    axes: true,
    grid: true,
    breaks: [],
  }
}

///|
pub fn has_graph_data(scene : Scene) -> Bool {
  scene.objects.values().any(fn(object) { object.kind == Graph }) ||
  scene.compositions
  .values()
  .any(fn(composition) {
    composition.states.values().any(fn(state) { state.graph is Some(_) })
  }) ||
  scene.transitions
  .values()
  .any(fn(transition) {
    transition.tracks
    .values()
    .any(fn(track) {
      track.graphTiming is Some(_) ||
      track.keyframes
      .map(fn(keys) {
        keys
        .values()
        .any(fn(key) {
          key.property is GraphA ||
          key.property is GraphB ||
          key.property is GraphC
        })
      })
      .unwrap_or(false)
    })
  })
}

///|
pub fn graph_value_error(graph : GraphDefinition) -> String? {
  if graph.syntaxVersion != 1 {
    return Some("対応していない数式のバージョンです。")
  }
  for
    value in [
      graph.xMin,
      graph.xMax,
      graph.yMin,
      graph.yMax,
      graph.a,
      graph.b,
      graph.c,
    ] +
    graph.breaks {
    if value.is_nan() || value.is_inf() || value.abs() > 100000.0 {
      return Some(
        "グラフの値は −100000〜100000 の有限な数値にしてください。",
      )
    }
  }
  if graph.xMax - graph.xMin < 1.0e-9 || graph.yMax - graph.yMin < 1.0e-9 {
    return Some(
      "軸の最大値は最小値より大きくしてください。",
    )
  }
  if graph.breaks.length() > 32 {
    return Some("不連続点は 32 個まで指定できます。")
  }
  None
}

///|
pub fn graph_validation_error(graph : GraphDefinition) -> String? {
  if graph_value_error(graph) is Some(message) {
    return Some(message)
  }
  try @math_plot.prepare(graph.expression) |> ignore catch {
    @math_plot.InvalidExpression(message) => return Some(message)
  }
  None
}

///|
pub fn parse_graph_breaks(source : String) -> Array[Double] raise InvalidGraph {
  if source.length() > 512 {
    raise InvalidGraph("不連続点の指定が長すぎます。")
  }
  let result : Array[Double] = []
  if source.trim().is_empty() {
    return result
  }
  for piece in source.split(",") {
    let value = @string.parse_double(piece.trim()) catch {
      _ =>
        raise InvalidGraph(
          "不連続点は数値をカンマで区切って指定してください。",
        )
    }
    if value.is_nan() || value.is_inf() || value.abs() > 100000.0 {
      raise InvalidGraph("不連続点の値が無効です。")
    }
    result.push(value)
  }
  if result.length() > 32 {
    raise InvalidGraph("不連続点は 32 個まで指定できます。")
  }
  result
}

///|
fn interpolate_graph(
  a : GraphDefinition?,
  b : GraphDefinition?,
  progress : Double,
  discrete : Double,
  interpolate : (Double, Double, Double) -> Double,
) -> GraphDefinition? {
  if a is None && b is None {
    return None
  }
  let a = a.unwrap_or(default_graph())
  let b = b.unwrap_or(default_graph())
  Some({
    ..(if discrete < 0.5 { a } else { b }),
    a: interpolate(a.a, b.a, progress),
    b: interpolate(a.b, b.b, progress),
    c: interpolate(a.c, b.c, progress),
  })
}

///|
pub(all) suberror InvalidGraph {
  InvalidGraph(String)
} derive(Debug)
