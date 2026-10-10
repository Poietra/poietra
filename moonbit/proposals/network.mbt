///|
fn read_network_operation(
  input : @core.Any,
  cid : String,
  oid : String,
) -> @plan.Operation {
  let collection : String = input._get("collection").cast()
  let value = input._get("element")
  let element = if @core.is_nullish(value) {
    None
  } else if collection == "nodes" {
    if @core.typeof_(value._get("x")) != "number" ||
      @core.typeof_(value._get("y")) != "number" {
      return fail("ノードの座標が必要です。")
    }
    Some(
      @plan.NodeElement({
        x: value._get("x").cast(),
        y: value._get("y").cast(),
        label: value._get("label").cast(),
        deleted: Some(false),
      }),
    )
  } else if collection == "edges" {
    if @core.typeof_(value._get("from")) != "string" ||
      @core.typeof_(value._get("to")) != "string" ||
      @core.typeof_(value._get("directed")) != "boolean" ||
      @core.typeof_(value._get("bend")) != "number" {
      return fail("辺の参照・向き・曲がりが必要です。")
    }
    Some(
      @plan.EdgeElement({
        from: value._get("from").cast(),
        to: value._get("to").cast(),
        label: value._get("label").cast(),
        directed: value._get("directed").cast(),
        bend: value._get("bend").cast(),
        weight: if @core.is_nullish(value._get("weight")) {
          None
        } else {
          Some(value._get("weight").cast())
        },
        deleted: Some(false),
      }),
    )
  } else {
    return fail("グラフ理論の図の要素が不正です。")
  }
  @plan.NetworkElement(
    cid,
    oid,
    collection,
    input._get("elementId").cast(),
    element,
  )
}
