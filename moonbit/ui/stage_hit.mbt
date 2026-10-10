///|
// Use the presented SVG path, rather than sampling the expression again. The
// native adapter caches screen-space Path2D geometry without changing the DOM.
extern "js" fn stage_curve_hit(
  curve : @core.Any,
  x : Double,
  y : Double,
) -> Bool =
  #|(() => {
  #|  const paths = new WeakMap();
  #|  let context;
  #|  return (curve, x, y) => {
  #|    const source = curve.getAttribute('d');
  #|    const matrix = curve.getScreenCTM();
  #|    if (!source || !matrix) return false;
  #|    const style = getComputedStyle(curve);
  #|    if (style.stroke === 'none' || parseFloat(style.strokeWidth) <= 0 || style.visibility !== 'visible') return false;
  #|    const transform = [matrix.a, matrix.b, matrix.c, matrix.d, matrix.e, matrix.f].join(',');
  #|    let cached = paths.get(curve);
  #|    if (!cached || cached.source !== source || cached.transform !== transform) {
  #|      const local = cached?.source === source ? cached.local : new Path2D(source);
  #|      const screen = new Path2D();
  #|      screen.addPath(local, matrix);
  #|      cached = { source, transform, local, screen };
  #|      paths.set(curve, cached);
  #|    }
  #|    context ??= document.createElement('canvas').getContext('2d');
  #|    if (!context) return false;
  #|    context.lineWidth = 12;
  #|    context.lineCap = 'round';
  #|    context.lineJoin = 'round';
  #|    return context.isPointInStroke(cached.screen, x, y);
  #|  };
  #|})()

///|
fn stage_graph_point_visible(item : @core.Any, at : @scene.Point) -> Bool {
  let value = item._get("clips")
  if !@core.is_nullish(value) {
    let clips : FixedArray[@core.Any] = value.cast()
    for clip in clips {
      let width : Double = clip._get("width").cast()
      let height : Double = clip._get("height").cast()
      if !@geometry.point_in_matrix_bounds(
          at,
          { x: -width / 2.0, y: -height / 2.0, width, height, },
          { x: 0.0, y: 0.0, },
          @boundary.read_affine(clip._get("world")),
        ) {
        return false
      }
    }
  }
  true
}

///|
// Supplemental graph hits run after painted-object and existing bounds hits,
// so an enlarged curve/selected viewport cannot steal another object's click.
fn StageController::graph_hit(
  self : StageController,
  at : @scene.Point,
) -> String? {
  guard self.surface.get_current() is Some(surface) else { return None }
  let objects : FixedArray[@core.Any] = self.frame._get("objects").cast()
  let mut curves : Map[String, @core.Any]? = None
  for index = objects.length() - 1; index >= 0; index = index - 1 {
    let item = objects[index]
    let object = item._get("object")
    if @boundary.read_object_kind(object._get("kind")) != @scene.Graph {
      continue
    }
    let state = item._get("state")
    let opacity : Double = state._get("opacity").cast()
    let progress : Double = item._get("writeProgress").cast()
    if !truthy(state._get("visible")) ||
      opacity <= 0.0 ||
      progress <= 0.0 ||
      !stage_graph_point_visible(item, at) {
      continue
    }
    let id : String = object._get("id").cast()
    if self.state_editing &&
      self.selected.iter().any(fn(selected) { selected == id }) &&
      @geometry.point_in_matrix_bounds(
        at,
        stage_bounds(self.renderer._call("objectBounds", [item])),
        { x: state._get("x").cast(), y: state._get("y").cast(), },
        stage_item_matrix(item),
      ) {
      return Some(id)
    }
    if curves is None {
      let found : Map[String, @core.Any] = Map([])
      let paths : FixedArray[@core.Any] = surface
        ._call("querySelectorAll", [@core.any(".scene-svg [data-graph-curve]")])
        .cast()
      for path in paths {
        let object = path._call("closest", [@core.any("[data-object-id]")])
        if truthy(object) {
          let id : String = object
            ._call("getAttribute", [@core.any("data-object-id")])
            .cast()
          found[id] = path
        }
      }
      curves = Some(found)
    }
    if curves.unwrap().get(id) is Some(curve) {
      let rect = stage_bounds(surface._call("getBoundingClientRect", []))
      if stage_curve_hit(
          curve,
          rect.x + at.x / self.width * rect.width,
          rect.y + at.y / self.height * rect.height,
        ) {
        return Some(id)
      }
    }
  }
  None
}
