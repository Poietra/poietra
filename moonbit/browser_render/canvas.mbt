///|
#external
priv type CanvasPath

///|
extern "js" fn canvas_path(data : String) -> CanvasPath =
  #|data => new Path2D(data)

///|
extern "js" fn path_ellipse(path : CanvasPath, x : Double, y : Double) -> Unit =
  #|(path, x, y) => { path.ellipse(0, 0, x, y, 0, 0, Math.PI * 2); path.closePath(); }

///|
extern "js" fn fill_path(
  context : @canvas.CanvasRenderingContext2D,
  path : CanvasPath,
) -> Unit =
  #|(context, path) => context.fill(path)

///|
extern "js" fn stroke_path(
  context : @canvas.CanvasRenderingContext2D,
  path : CanvasPath,
) -> Unit =
  #|(context, path) => context.stroke(path)

///|
extern "js" fn canvas_dash(
  context : @canvas.CanvasRenderingContext2D,
  dash : FixedArray[Double],
  offset : Double,
) -> Unit =
  #|(context, dash, offset) => { context.setLineDash(dash); context.lineDashOffset = offset; }

///|
extern "js" fn round_caps(context : @canvas.CanvasRenderingContext2D) -> Unit =
  #|context => { context.lineCap = 'round'; context.lineJoin = 'round'; }

///|
/// Bracket a native resource even when a browser API throws a JavaScript exception.
extern "js" fn saved_canvas(
  context : @canvas.CanvasRenderingContext2D,
  paint : () -> Unit,
) -> Unit =
  #|(context, paint) => { context.save(); try { paint(); } finally { context.restore(); } }

///|
extern "js" fn numeric_string(value : String) -> Double = "Number"

///|
fn svg_element(tag : String) -> @core.Any {
  @core.global_this()
  ._get("document")
  ._call("createElementNS", [
    @core.any("http://www.w3.org/2000/svg"),
    @core.any(tag),
  ])
}

///|
fn[T] unsupported(message : String) -> T {
  @core.throw_error(message)
  panic()
}

///|
fn path_length(data : String) -> Double {
  let element = svg_element("path")
  element._call("setAttribute", [@core.any("d"), @core.any(data)]) |> ignore
  let length : Double = element._call("getTotalLength", []).cast()
  if length.is_nan() || length.is_inf() {
    return unsupported("Unsupported shape length.")
  }
  length
}

///|
fn canvas_available() -> Bool {
  let global = @core.global_this()
  !@core.is_undefined(global._get("document")) &&
  !@core.is_undefined(global._get("Path2D"))
}

///|
extern "js" fn path_rect(
  path : CanvasPath,
  x : Double,
  y : Double,
  width : Double,
  height : Double,
) -> Unit =
  #|(path, x, y, width, height) => path.rect(x, y, width, height)

///|
#external
priv type CanvasMatrix

///|
extern "js" fn canvas_matrix() -> CanvasMatrix =
  #|() => new DOMMatrix()

///|
extern "js" fn apply_matrix(
  context : @canvas.CanvasRenderingContext2D,
  matrix : CanvasMatrix,
) -> Unit =
  #|(context, matrix) => context.transform(matrix.a, matrix.b, matrix.c, matrix.d, matrix.e, matrix.f)

///|
priv struct Outline {
  path : CanvasPath
  length : Double
}

///|
fn outline(shape : @render.Shape) -> Outline {
  match @render.outline_source(shape) {
    Empty => { path: canvas_path(""), length: 0.0, }
    Ellipse(x, y, source) => {
      let length = path_length(source)
      let path = canvas_path("")
      path_ellipse(
        path,
        numeric_string(@render.number(x)),
        numeric_string(@render.number(y)),
      )
      { path, length, }
    }
    Measured(source) =>
      { path: canvas_path(source), length: path_length(source), }
    Shaft(source, length) =>
      {
        path: canvas_path(source),
        length: numeric_string(@render.number(length)),
      }
  }
}
