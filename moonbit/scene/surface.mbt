///|
pub(all) enum SurfaceKind {
  Heightfield
  Parametric
} derive(Eq)

///|
pub fn surface_kind(value : String) -> SurfaceKind? {
  match value {
    "heightfield" => Some(Heightfield)
    "parametric" => Some(Parametric)
    _ => None
  }
}

///|
pub fn surface_kind_name(value : SurfaceKind) -> String {
  match value {
    Heightfield => "heightfield"
    Parametric => "parametric"
  }
}

///|
pub impl ToJson for SurfaceKind with fn to_json(self) {
  surface_kind_name(self).to_json()
}

///|
pub impl @json.FromJson for SurfaceKind with fn from_json(value, path) {
  let text : String = @json.from_json(value, path~)
  match surface_kind(text) {
    Some(value) => value
    None => raise @json.JsonDecodeError((path, "Unknown surface kind"))
  }
}

///|
pub fn default_surface() -> SurfaceDefinition {
  {
    version: 1,
    kind: Heightfield,
    xExpression: "u",
    yExpression: "v",
    zExpression: "a*sin(x)*cos(y)",
    uMin: -3.0,
    uMax: 3.0,
    vMin: -3.0,
    vMax: 3.0,
    a: 1.0,
    b: 0.0,
    c: 0.0,
    yaw: 35.0,
    pitch: 35.0,
    zoom: 1.0,
    steps: 20,
    filled: true,
    wireframe: true,
    axes: true,
  }
}

///|
pub fn surface_preset(name : String) -> SurfaceDefinition {
  let value = default_surface()
  match name {
    "sphere" =>
      {
        ..value,
        kind: Parametric,
        xExpression: "a*cos(u)*sin(v)",
        yExpression: "a*sin(u)*sin(v)",
        zExpression: "a*cos(v)",
        uMin: 0.0,
        uMax: 2.0 * @math.PI,
        vMin: 0.0,
        vMax: @math.PI,
        a: 2.0,
      }
    "torus" =>
      {
        ..value,
        kind: Parametric,
        xExpression: "(a+b*cos(v))*cos(u)",
        yExpression: "(a+b*cos(v))*sin(u)",
        zExpression: "b*sin(v)",
        uMin: 0.0,
        uMax: 2.0 * @math.PI,
        vMin: 0.0,
        vMax: 2.0 * @math.PI,
        a: 2.0,
        b: 0.7,
      }
    "saddle" => { ..value, zExpression: "a*(x^2-y^2)/4", }
    _ => value
  }
}

///|
pub fn surface_validation_error(value : SurfaceDefinition) -> String? {
  if value.version != 1 || value.steps < 4 || value.steps > 48 {
    return Some(
      "曲面の分割数は4〜48、バージョンは1を指定してください。",
    )
  }
  for
    v in [
      value.uMin,
      value.uMax,
      value.vMin,
      value.vMax,
      value.a,
      value.b,
      value.c,
      value.yaw,
      value.pitch,
      value.zoom,
    ] {
    if v.is_nan() || v.is_inf() || v.abs() > 100000.0 {
      return Some(
        "曲面の値は有限の数値（±100000以内）にしてください。",
      )
    }
  }
  if value.uMax - value.uMin < 1.0e-9 ||
    value.vMax - value.vMin < 1.0e-9 ||
    value.zoom < 0.05 ||
    value.zoom > 10.0 ||
    value.pitch < -89.0 ||
    value.pitch > 89.0 ||
    (!value.filled && !value.wireframe) {
    return Some(
      "曲面の範囲・視点・表示方法を確認してください。",
    )
  }
  try
    @math_surface.prepare(
      value.xExpression,
      value.yExpression,
      value.zExpression,
      value.kind == Heightfield,
    )
    |> ignore
  catch {
    @math_plot.InvalidExpression(message) => return Some(message)
  }
  if [value.xExpression, value.yExpression, value.zExpression].any(fn(s) {
      s.length() > 512 || s.is_empty()
    }) {
    return Some("曲面の式は1〜512文字で指定してください。")
  }
  None
}

///|
fn interpolate_surface(
  a : SurfaceDefinition?,
  b : SurfaceDefinition?,
  progress : Double,
  discrete : Double,
  interpolate : (Double, Double, Double) -> Double,
) -> SurfaceDefinition? {
  if a is None && b is None {
    return None
  }
  let a = a.unwrap_or(default_surface())
  let b = b.unwrap_or(default_surface())
  Some({
    ..(if discrete < 0.5 { a } else { b }),
    a: interpolate(a.a, b.a, progress),
    b: interpolate(a.b, b.b, progress),
    c: interpolate(a.c, b.c, progress),
    yaw: interpolate(a.yaw, b.yaw, progress),
    pitch: interpolate(a.pitch, b.pitch, progress),
    zoom: interpolate(a.zoom, b.zoom, progress),
  })
}
