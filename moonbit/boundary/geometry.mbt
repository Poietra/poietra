///|
fn placement(value : @core.Any) -> @geometry.Placement {
  {
    x: value._get("x").cast(),
    y: value._get("y").cast(),
    rotation: value._get("rotation").cast(),
  }
}

///|
fn rectangle(value : @core.Any) -> @geometry.Rectangle {
  {
    x: value._get("x").cast(),
    y: value._get("y").cast(),
    width: value._get("width").cast(),
    height: value._get("height").cast(),
  }
}

///|
fn rectangle_value(value : @geometry.Rectangle) -> @core.Any {
  @core.from_entries([
    ("x", @core.any(value.x)),
    ("y", @core.any(value.y)),
    ("width", @core.any(value.width)),
    ("height", @core.any(value.height)),
  ])
}

///|
pub fn rotate_vector(point : @core.Any, degrees : Double) -> @core.Any {
  @project_codec.encode_Point(
    @geometry.rotate(@project_codec.decode_Point(point), degrees),
  )
}

///|
pub fn world_to_local(point : @core.Any, state : @core.Any) -> @core.Any {
  @project_codec.encode_Point(
    @geometry.world_to_local(
      @project_codec.decode_Point(point),
      placement(state),
    ),
  )
}

///|
pub fn local_to_world(point : @core.Any, state : @core.Any) -> @core.Any {
  @project_codec.encode_Point(
    @geometry.local_to_world(
      @project_codec.decode_Point(point),
      placement(state),
    ),
  )
}

///|
pub fn point_in_rotated_bounds(
  point : @core.Any,
  bounds : @core.Any,
  state : @core.Any,
) -> Bool {
  @geometry.point_in_bounds(
    @project_codec.decode_Point(point),
    rectangle(bounds),
    placement(state),
  )
}

///|
pub fn rectangle_from_points(a : @core.Any, b : @core.Any) -> @core.Any {
  rectangle_value(
    @geometry.rectangle_from_points(
      @project_codec.decode_Point(a),
      @project_codec.decode_Point(b),
    ),
  )
}

///|
pub fn rectangle_contains_rotated_bounds(
  area : @core.Any,
  bounds : @core.Any,
  state : @core.Any,
) -> Bool {
  @geometry.rectangle_contains_bounds(
    rectangle(area),
    rectangle(bounds),
    placement(state),
  )
}

///|
pub fn resize_from_corner(
  state : @core.Any,
  size : @core.Any,
  corner : String,
  delta : @core.Any,
  preserve_aspect : Bool,
  text : Bool,
) -> @core.Any {
  let result = @geometry.resize_from_corner(
    @project_codec.decode_ObjectState(state),
    size._get("width").cast(),
    size._get("height").cast(),
    corner,
    @project_codec.decode_Point(delta),
    preserve_aspect,
    text,
  )
  let value = @core.from_entries([
    ("x", @core.any(result.x)),
    ("y", @core.any(result.y)),
    ("width", @core.any(result.width)),
    ("height", @core.any(result.height)),
  ])
  if result.font_size is Some(size) {
    value._set("fontSize", @core.any(size))
  }
  value
}

///|
pub fn rotation_from_pointer(
  state : @core.Any,
  start : @core.Any,
  at : @core.Any,
  snap : Bool,
) -> Double {
  @geometry.rotation_from_pointer(
    placement(state),
    @project_codec.decode_Point(start),
    @project_codec.decode_Point(at),
    snap,
  )
}
