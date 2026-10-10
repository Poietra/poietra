///|
fn read_geometry_operation(
  input : @core.Any,
  cid : String,
  oid : String,
) -> @plan.Operation {
  let collection : String = input._get("collection").cast()
  let value = input._get("element")
  let reference = fn(key : String) {
    if @core.is_nullish(value._get(key)) {
      None
    } else {
      Some(value._get(key).cast())
    }
  }
  let element = if @core.is_nullish(value) {
    None
  } else {
    if collection == "points" && @core.typeof_(value._get("kind")) != "string" {
      return fail("点の構成の種類が必要です。")
    }
    if collection != "points" &&
      (
        @core.typeof_(value._get("from")) != "string" ||
        @core.typeof_(value._get("to")) != "string"
      ) {
      return fail("参照する点のIDが必要です。")
    }
    if collection == "angles" && @core.typeof_(value._get("vertex")) != "string" {
      return fail("角度の頂点が必要です。")
    }
    Some(
      match collection {
        "points" =>
          @plan.PointElement({
            kind: @scene.geometry_point_kind(value._get("kind").cast()).unwrap(),
            x: value._get("x").cast(),
            y: value._get("y").cast(),
            from: reference("from"),
            to: reference("to"),
            label: value._get("label").cast(),
            deleted: Some(false),
          })
        "vectors" =>
          @plan.VectorElement({
            from: value._get("from").cast(),
            to: value._get("to").cast(),
            label: value._get("label").cast(),
            deleted: Some(false),
          })
        "angles" =>
          @plan.AngleElement({
            from: value._get("from").cast(),
            vertex: value._get("vertex").cast(),
            to: value._get("to").cast(),
            label: value._get("label").cast(),
            deleted: Some(false),
          })
        _ => fail("数学図の要素の種類が不正です。")
      },
    )
  }
  @plan.GeometryElement(
    cid,
    oid,
    collection,
    input._get("elementId").cast(),
    element,
  )
}
