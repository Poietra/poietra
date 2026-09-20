///|
fn transform_inspector(input : @core.Any) -> @react.Element {
  let editor = use_editor_state()
  let scene = editor._get("scene")
  let store = editor._get("store")
  let object = input._get("object")
  let state = @boundary.read_object_state(input._get("state"))
  let sid : String = scene._get("id").cast()
  let cid : String = editor._get("compositionId").cast()
  let id : String = object._get("id").cast()
  let (error, set_error) = @react.use_state("")
  let change = fn(action : String, args : FixedArray[@core.Any]) {
    attempt(
      fn() {
        store._call(action, args) |> ignore
        set_error("")
      },
      set_error,
      "Transform を変更できませんでした。",
    )
  }
  let update = fn(key : String, value : Double) {
    change("updateState", [
      @core.any(sid),
      @core.any(cid),
      @core.any(id),
      host_record(Map([(key, @core.any(value))])),
    ])
  }
  let anchor = fn(axis : String, value : Double) {
    let current = store
      ._call("scene", [@core.any(sid)])
      ._get("compositions")
      ._get(cid)
      ._get("states")
      ._get(id)
    let state = @boundary.read_object_state(current)
    change("setAnchor", [
      @core.any(sid),
      @core.any(cid),
      @core.any(id),
      @core.any(if axis == "x" { value } else { state.anchorX.unwrap_or(0.0) }),
      @core.any(if axis == "y" { value } else { state.anchorY.unwrap_or(0.0) }),
    ])
  }
  let choices : Array[&@react.ReactNode] = [export_choice("", "None")]
  for candidate in @boundary.ordered_objects(scene) {
    let other : String = candidate._get("id").cast()
    if other != id {
      choices.push(export_choice(other, string_value(candidate._get("name"))))
    }
  }
  let content : Array[&@react.ReactNode] = [
    component(field, { "label": @core.any("Parent · Scene") }, [
      h(
        "select",
        {
          "aria-label": @core.any("Parent object"),
          "value": @core.any(
            optional_string(object._get("parentId")).unwrap_or(""),
          ),
          "onChange": @core.any(fn(event : @core.Any) {
            let parent : String = event._get("target")._get("value").cast()
            change("setParent", [
              @core.any(sid),
              @core.any(id),
              if parent.is_empty() {
                @core.null()
              } else {
                @core.any(parent)
              },
            ])
          }),
        },
        choices,
      ),
    ]),
    h("p", { "className": @core.any("property-timing-note") }, [
      "親の移動・回転・拡縮に追従します。親の変更時は各 Composition の見た目を保ちます。",
    ]),
    h("div", { "className": @core.any("property-grid") }, [
      number_field(
        "Scale X",
        "Scale X",
        state.scaleX.unwrap_or(1.0) * 100.0,
        fn(v) { update("scaleX", v / 100.0) },
        suffix="%",
      ),
      number_field(
        "Scale Y",
        "Scale Y",
        state.scaleY.unwrap_or(1.0) * 100.0,
        fn(v) { update("scaleY", v / 100.0) },
        suffix="%",
      ),
    ]),
    h("div", { "className": @core.any("property-grid") }, [
      number_field(
        "Anchor X",
        "Anchor X",
        state.anchorX.unwrap_or(0.0),
        fn(v) { anchor("x", v) },
        suffix="px",
      ),
      number_field(
        "Anchor Y",
        "Anchor Y",
        state.anchorY.unwrap_or(0.0),
        fn(v) { anchor("y", v) },
        suffix="px",
      ),
    ]),
  ]
  if state.shear.unwrap_or(0.0).abs() > 0.000001 {
    content.push(
      number_field("Shear", "Transform shear", state.shear.unwrap_or(0.0), fn(
        v,
      ) {
        update("shear", v)
      }),
    )
  }
  if !error.is_empty() {
    content.push(
      h(
        "p",
        {
          "role": @core.any("alert"),
          "className": @core.any("property-timing-error"),
        },
        [error],
      ),
    )
  }
  inspector_section("Transform", content)
}
