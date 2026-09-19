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
  }
}

///|
pub fn validate_state(
  field : StateField,
  value : Scalar,
  kind : @scene.ObjectKind?,
) -> Unit raise CompileError {
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
