///|
fn scalar(value : @core.Any) -> @plan.Scalar {
  match @core.typeof_(value) {
    "number" => Number(value.cast())
    "string" => Text(value.cast())
    "boolean" => Boolean(value.cast())
    _ => fail("プロパティの形式または値が無効です。")
  }
}

///|
pub fn validate_state_value(
  property : String,
  value : @core.Any,
  kind : @core.Any,
) -> Unit {
  let field = match @plan.state_field(property) {
    Some(field) => field
    None => return fail("編集できないプロパティです。")
  }
  let kind = if @core.is_nullish(kind) {
    None
  } else {
    Some(@boundary.read_object_kind(kind))
  }
  @plan.validate_state(field, scalar(value), kind) catch {
    @plan.CompileError(message) => fail(message)
  }
}

///|
fn read_creation(input : @core.Any, action : String) -> @plan.Creation {
  let kind = if action == "createImage" {
    @scene.Image
  } else {
    @boundary.read_object_kind(input._get("kind"))
  }
  let state = @scene.default_state(kind)
  let state = {
    ..state,
    x: input._get("x").cast(),
    y: input._get("y").cast(),
    width: input._get("width").cast(),
    height: input._get("height").cast(),
  }
  let (state, image) = if kind == Image {
    let image = input._get("image")
    (
      {
        ..state,
        cornerRadius: 0.0,
        fill: "none",
        stroke: "#ffffff",
        strokeWidth: 0.0,
      },
      Some(@scene.ImageAsset::{
        src: image._get("src").cast(),
        width: image._get("width").cast(),
        height: image._get("height").cast(),
      }),
    )
  } else {
    (
      {
        ..state,
        fill: input._get("fill").cast(),
        text: input._get("text").cast(),
        fontSize: input._get("fontSize").cast(),
      },
      None,
    )
  }
  {
    reference: if action == "addObject" {
      None
    } else {
      Some(input._get("ref").cast())
    },
    composition: input._get("compositionId").cast(),
    name: input._get("name").cast(),
    kind,
    state,
    image,
  }
}

///|
fn read_operation(input : @core.Any) -> @plan.Operation {
  let action : String = input._get("action").cast()
  let cid : String = input._get("compositionId").cast()
  let tid : String = input._get("transitionId").cast()
  let oid : String = input._get("objectId").cast()
  match action {
    "createObject" | "addObject" | "createImage" =>
      Create(read_creation(input, action))
    "appendComposition" =>
      Append(
        input._get("ref").cast(),
        input._get("transitionRef").cast(),
        input._get("name").cast(),
        input._get("duration").cast(),
        input._get("transitionDuration").cast(),
      )
    "setState" =>
      State(
        cid,
        oid,
        @plan.state_field(input._get("property").cast()).unwrap(),
        scalar(input._get("value")),
      )
    "setParent" =>
      Parent(
        oid,
        if @core.is_nullish(input._get("parentId")) {
          None
        } else {
          Some(input._get("parentId").cast())
        },
      )
    "setAnchor" =>
      Anchor(cid, oid, input._get("x").cast(), input._get("y").cast())
    "setShapePath" =>
      ShapePath(cid, oid, @boundary.read_bezier(input._get("path")))
    "setMotionPath" =>
      Track(
        tid,
        oid,
        MotionPath(
          if @core.is_nullish(input._get("path")) {
            None
          } else {
            Some(@boundary.read_bezier(input._get("path")))
          },
        ),
      )
    "setKeyframe" =>
      Track(
        tid,
        oid,
        KeyframeEdit(
          input._get("keyframeId").cast(),
          if @core.is_nullish(input._get("keyframe")) {
            None
          } else {
            Some(@boundary.read_keyframe(input._get("keyframe")))
          },
        ),
      )
    "setPropertyTiming" =>
      Track(
        tid,
        oid,
        PropertyTiming(
          @scene.property_channel(input._get("channel").cast()).unwrap(),
          if @core.is_nullish(input._get("timing")) {
            None
          } else {
            Some(@boundary.read_timing(input._get("timing")))
          },
        ),
      )
    "setCompositionDuration" =>
      CompositionDuration(cid, input._get("duration").cast())
    "setTransitionDuration" =>
      TransitionDuration(tid, input._get("duration").cast())
    "setTrack" => {
      let value = input._get("value")
      let edit = match (input._get("property").cast() : String) {
        "type" => {
          if @core.typeof_(value) != "string" {
            return fail("アニメーションの種類が無効です。")
          }
          match @scene.animation_kind(value.cast()) {
            Some(kind) => @plan.Kind(kind)
            None =>
              return fail("アニメーションの種類が無効です。")
          }
        }
        "easing" => {
          if !@boundary.is_valid_easing(value) {
            return fail("イージングの形式が無効です。")
          }
          Easing(@boundary.read_easing(value))
        }
        "order" => {
          if @core.typeof_(value) != "string" {
            return fail("アニメーションの順序が無効です。")
          }
          let order : String = value.cast()
          if order != "together" && order != "sequential" {
            return fail("アニメーションの順序が無効です。")
          }
          Order(order)
        }
        property => {
          if @core.typeof_(value) != "number" {
            return fail(
              "アニメーションの時刻は数値で指定してください。",
            )
          }
          if property == "start" {
            Start(value.cast())
          } else {
            Duration(value.cast())
          }
        }
      }
      Track(tid, oid, edit)
    }
    _ => fail("編集できない操作です。")
  }
}
