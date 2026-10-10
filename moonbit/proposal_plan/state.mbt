///|
pub fn state_field(value : String) -> StateField? {
  match value {
    "x" => Some(X)
    "y" => Some(Y)
    "width" => Some(Width)
    "height" => Some(Height)
    "rotation" => Some(Rotation)
    "opacity" => Some(Opacity)
    "visible" => Some(Visible)
    "fill" => Some(Fill)
    "stroke" => Some(Stroke)
    "strokeWidth" => Some(StrokeWidth)
    "text" => Some(TextContent)
    "fontSize" => Some(FontSize)
    "cornerRadius" => Some(CornerRadius)
    "effect" => Some(Effect)
    "anchorX" => Some(AnchorX)
    "anchorY" => Some(AnchorY)
    "scaleX" => Some(ScaleX)
    "scaleY" => Some(ScaleY)
    "shear" => Some(Shear)
    "graphExpression" => Some(GraphExpression)
    "graphXMin" => Some(GraphXMin)
    "graphXMax" => Some(GraphXMax)
    "graphYMin" => Some(GraphYMin)
    "graphYMax" => Some(GraphYMax)
    "graphA" => Some(GraphA)
    "graphB" => Some(GraphB)
    "graphC" => Some(GraphC)
    "graphAxes" => Some(GraphAxes)
    "graphGrid" => Some(GraphGrid)
    "graphBreaks" => Some(GraphBreaks)
    _ => None
  }
}

///|
pub fn field_name(value : StateField) -> String {
  match value {
    X => "x"
    Y => "y"
    Width => "width"
    Height => "height"
    Rotation => "rotation"
    Opacity => "opacity"
    Visible => "visible"
    Fill => "fill"
    Stroke => "stroke"
    StrokeWidth => "strokeWidth"
    TextContent => "text"
    FontSize => "fontSize"
    CornerRadius => "cornerRadius"
    Effect => "effect"
    AnchorX => "anchorX"
    AnchorY => "anchorY"
    ScaleX => "scaleX"
    ScaleY => "scaleY"
    Shear => "shear"
    GraphExpression => "graphExpression"
    GraphXMin => "graphXMin"
    GraphXMax => "graphXMax"
    GraphYMin => "graphYMin"
    GraphYMax => "graphYMax"
    GraphA => "graphA"
    GraphB => "graphB"
    GraphC => "graphC"
    GraphAxes => "graphAxes"
    GraphGrid => "graphGrid"
    GraphBreaks => "graphBreaks"
  }
}

///|
pub fn validate_state(
  field : StateField,
  value : Scalar,
  kind : @scene.ObjectKind?,
) -> Unit raise CompileError {
  if graph_field_key(field) is Some(_) {
    if kind is Some(kind) && kind != Graph {
      raise CompileError("関数グラフを選択してください。")
    }
    match (field, value) {
      (GraphExpression, Text(source)) => {
        let graph = {
          ..@scene.default_graph(),
          expression: source,
          syntaxVersion: @scene.graph_expression_version(source),
        }
        if @scene.graph_validation_error(graph) is Some(message) {
          raise CompileError(message)
        }
      }
      (GraphBreaks, Text(source)) =>
        try @scene.parse_graph_breaks(source) |> ignore catch {
          @scene.InvalidGraph(message) => raise CompileError(message)
        }
      (GraphAxes | GraphGrid, Boolean(_)) => ()
      (
        GraphXMin
        | GraphXMax
        | GraphYMin
        | GraphYMax
        | GraphA
        | GraphB
        | GraphC,
        Number(value),
      ) if @assets.bounded_number(value, -100000.0, 100000.0) => ()
      _ => raise CompileError("グラフの属性の値が無効です。")
    }
    return
  }
  if (kind == Some(Image) || kind == Some(Video)) &&
    (field == Fill || field == TextContent || field == FontSize) {
    let name = if kind == Some(Video) { "動画" } else { "画像" }
    raise CompileError(
      name +
      "の色や内容は変更できません。配置・サイズ・表示・動きを調整してください。",
    )
  }
  match (field, value) {
    (Fill | Stroke, Text(color)) if color.length() == 7 &&
      @assets.document_color(color) => ()
    (TextContent, Text(text)) if text.length() <= 3000 => ()
    (Effect, Text("none" | "glow")) => ()
    (Visible, Boolean(_)) => ()
    (
      X
      | Y
      | Width
      | Height
      | Rotation
      | Opacity
      | StrokeWidth
      | FontSize
      | CornerRadius
      | AnchorX
      | AnchorY
      | ScaleX
      | ScaleY
      | Shear,
      Number(number),
    ) if @assets.bounded_number(number, -10000.0, 10000.0) => {
      let endpoint = kind == Some(Path) ||
        kind == Some(Arrow) ||
        kind == Some(NumberLine)
      if (
          field == FontSize ||
          field == CornerRadius ||
          field == StrokeWidth ||
          (!endpoint && (field == Width || field == Height))
        ) &&
        number < 0.0 {
        raise CompileError(
          "サイズは 0 以上で指定してください。",
        )
      }
      if field == Opacity && (number < 0.0 || number > 1.0) {
        raise CompileError(
          "不透明度は 0〜1 で指定してください。",
        )
      }
    }
    _ =>
      raise CompileError(
        "プロパティの形式または値が無効です。",
      )
  }
}

///|
fn change_state(
  state : @scene.ObjectState,
  field : StateField,
  value : Scalar,
  kind : @scene.ObjectKind,
) -> @scene.ObjectState raise CompileError {
  validate_state(field, value, Some(kind))
  if graph_field_key(field) is Some(_) {
    let graph = state.graph.unwrap_or(@scene.default_graph())
    let graph = match (field, value) {
      (GraphExpression, Text(expression)) =>
        {
          ..graph,
          expression,
          syntaxVersion: graph.syntaxVersion.max(
            @scene.graph_expression_version(expression),
          ),
        }
      (GraphXMin, Number(xMin)) => { ..graph, xMin, }
      (GraphXMax, Number(xMax)) => { ..graph, xMax, }
      (GraphYMin, Number(yMin)) => { ..graph, yMin, }
      (GraphYMax, Number(yMax)) => { ..graph, yMax, }
      (GraphA, Number(a)) => { ..graph, a, }
      (GraphB, Number(b)) => { ..graph, b, }
      (GraphC, Number(c)) => { ..graph, c, }
      (GraphAxes, Boolean(axes)) => { ..graph, axes, }
      (GraphGrid, Boolean(grid)) => { ..graph, grid, }
      (GraphBreaks, Text(source)) =>
        {
          ..graph,
          breaks: @scene.parse_graph_breaks(source) catch {
            @scene.InvalidGraph(message) => raise CompileError(message)
          },
        }
      _ => raise CompileError("グラフの属性の値が無効です。")
    }
    return { ..state, graph: Some(graph), }
  }
  match (field, value) {
    (AnchorX, Number(value)) => { ..state, anchorX: Some(value), }
    (AnchorY, Number(value)) => { ..state, anchorY: Some(value), }
    (ScaleX, Number(value)) => { ..state, scaleX: Some(value), }
    (ScaleY, Number(value)) => { ..state, scaleY: Some(value), }
    (Shear, Number(value)) => { ..state, shear: Some(value), }
    (X, Number(x)) => { ..state, x, }
    (Y, Number(y)) => { ..state, y, }
    (Width, Number(width)) => { ..state, width, }
    (Height, Number(height)) => { ..state, height, }
    (Rotation, Number(rotation)) => { ..state, rotation, }
    (Opacity, Number(opacity)) => { ..state, opacity, }
    (Visible, Boolean(visible)) => { ..state, visible, }
    (Fill, Text(fill)) => { ..state, fill, }
    (Stroke, Text(stroke)) => { ..state, stroke, }
    (StrokeWidth, Number(strokeWidth)) => { ..state, strokeWidth, }
    (TextContent, Text(text)) => { ..state, text, }
    (FontSize, Number(fontSize)) => { ..state, fontSize, }
    (CornerRadius, Number(cornerRadius)) => { ..state, cornerRadius, }
    (Effect, Text(effect)) =>
      { ..state, effect: if effect == "glow" { Glow } else { Normal }, }
    _ =>
      raise CompileError(
        "プロパティの形式または値が無効です。",
      )
  }
}

///|
fn valid_duration(value : Double) -> Unit raise CompileError {
  if !@assets.bounded_number(value, 0.0, 120000.0) {
    raise CompileError(
      "長さは 0〜120000 ms の有限な数値で指定してください。",
    )
  }
}

///|
pub fn graph_field_key(field : StateField) -> String? {
  match field {
    GraphExpression => Some("expression")
    GraphXMin => Some("xMin")
    GraphXMax => Some("xMax")
    GraphYMin => Some("yMin")
    GraphYMax => Some("yMax")
    GraphA => Some("a")
    GraphB => Some("b")
    GraphC => Some("c")
    GraphAxes => Some("axes")
    GraphGrid => Some("grid")
    GraphBreaks => Some("breaks")
    _ => None
  }
}
