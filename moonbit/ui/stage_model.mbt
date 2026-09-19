///|
priv struct StagePresentation {
  key : String
  width : Double
  height : Double
  frame : @core.Any
}

///|
priv struct StageMarquee {
  initial : Array[String]
  additive : Bool
  mut active : Bool
}

///|
priv enum StageMode {
  MoveObjects(Map[String, @scene.Point])
  DrawObject(@scene.ObjectKind)
  SelectArea(StageMarquee)
  EditPath(String, @editor.CurvePoint, String?)
  TransformObject(
    String,
    @editor.StageTransform,
    @scene.ObjectState,
    Double,
    Double
  )
}

///|
priv struct StageGesture {
  pointer : Int
  scene_id : String
  composition_id : String
  start : @scene.Point
  mode : StageMode
  element : @core.Any
  undo_before : @core.Any
  mut undo : @core.Any
  mut changed : Bool
  mut feedback : @editor.OperationStatus?
}

///|
priv struct StageController {
  editor : @core.Any
  scene : @core.Any
  store : @core.Any
  renderer : @core.Any
  frame : @core.Any
  surface : @react.ReactRef[@core.Any]
  gesture : @react.ReactRef[StageGesture]
  cursor_time : @react.ReactRef[Double]
  scene_id : String
  composition_id : String
  tool : @editor.StageTool
  can_edit : Bool
  state_editing : Bool
  selected : FixedArray[String]
  width : Double
  height : Double
  scale : Double
  draw : (@scene.ObjectState?) -> Unit
  marquee : (@geometry.Rectangle?) -> Unit
  hover : (String?) -> Unit
  report : (@core.Any) -> Unit
}

///|
fn stage_point(value : @scene.Point) -> @core.Any {
  host_record({ "x": @core.any(value.x), "y": @core.any(value.y) })
}

///|
fn stage_bounds(value : @core.Any) -> @geometry.Rectangle {
  {
    x: value._get("x").cast(),
    y: value._get("y").cast(),
    width: value._get("width").cast(),
    height: value._get("height").cast(),
  }
}

///|
fn stage_placement(value : @core.Any) -> @geometry.Placement {
  {
    x: value._get("x").cast(),
    y: value._get("y").cast(),
    rotation: value._get("rotation").cast(),
  }
}

///|
fn StageController::select(
  self : StageController,
  ids : FixedArray[String],
) -> Unit {
  self.editor._get("setSelectedIds")._invoke([@core.any(ids)]) |> ignore
}

///|
fn StageController::point(
  self : StageController,
  event : @core.Any,
) -> @scene.Point? {
  guard self.surface.get_current() is Some(surface) else { return None }
  let rect = stage_bounds(surface._call("getBoundingClientRect", []))
  if rect.width <= 0.0 || rect.height <= 0.0 {
    return None
  }
  let x : Double = event._get("clientX").cast()
  let y : Double = event._get("clientY").cast()
  Some({
    x: (x - rect.x) / rect.width * self.width,
    y: (y - rect.y) / rect.height * self.height,
  })
}

///|
fn StageController::hit(
  self : StageController,
  at : @scene.Point,
  target : @core.Any,
) -> String? {
  let direct = target._call("closest", [@core.any("[data-object-id]")])
  let direct = if truthy(direct) {
    optional_string(direct._call("getAttribute", [@core.any("data-object-id")]))
  } else {
    None
  }
  let objects : FixedArray[@core.Any] = self.frame._get("objects").cast()
  for index = objects.length() - 1; index >= 0; index = index - 1 {
    let item = objects[index]
    let state = item._get("state")
    let opacity : Double = state._get("opacity").cast()
    let progress : Double = item._get("writeProgress").cast()
    if !truthy(state._get("visible")) || opacity <= 0.0 || progress <= 0.0 {
      continue
    }
    let object = item._get("object")
    let id : String = object._get("id").cast()
    if direct == Some(id) {
      return direct
    }
    let kind = @boundary.read_object_kind(object._get("kind"))
    if (kind is Text || kind is Equation || kind is Image || kind is Video) &&
      @geometry.point_in_bounds(
        at,
        stage_bounds(self.renderer._call("objectBounds", [item])),
        stage_placement(state),
      ) {
      return Some(id)
    }
  }
  None
}
