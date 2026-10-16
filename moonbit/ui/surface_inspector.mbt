///|
priv struct SurfaceInspectorView {
  controller : InspectorController
  definition : @scene.SurfaceDefinition
  width : Double
  height : Double
  fill : String
}

///|
let surface_inspector_component : TypedComponent[SurfaceInspectorView] = memo_typed_component(
  surface_inspector,
)

///|
priv struct SurfaceExpressionView {
  name : String
  value : String
  apply : (String, () -> Unit) -> Unit
  clear_error : () -> Unit
}

///|
let surface_expression_component : TypedComponent[SurfaceExpressionView] = memo_typed_component(
  surface_expression,
)

///|
fn surface_expression(input : SurfaceExpressionView) -> @react.Element {
  let (draft, set_draft) = @react.use_state((None : String?))
  let dirty = @react.use_ref(Some(false))
  h(
    "input",
    {
      "aria-label": @core.any("Surface " + input.name + " expression"),
      "className": @core.any("content-input"),
      "spellCheck": @core.any(false),
      "maxLength": @core.any(512),
      "value": @core.any(draft.unwrap_or(input.value)),
      "onFocus": @core.any(fn() { dirty.set_current(Some(false)) }),
      "onChange": @core.any(fn(e : @core.Any) {
        dirty.set_current(Some(true))
        set_draft(Some(e._get("target")._get("value").cast()))
        (input.clear_error)()
      }),
      "onBlur": @core.any(fn(e : @core.Any) {
        if dirty.get_current() == Some(true) {
          (input.apply)(e._get("target")._get("value").cast(), fn() {
            dirty.set_current(Some(false))
            set_draft(None)
          })
        }
      }),
      "onKeyDown": @core.any(fn(e : @core.Any) {
        let key : String = e._get("key").cast()
        if key == "Enter" {
          e._get("currentTarget")._call("blur", []) |> ignore
        } else if key == "Escape" {
          e._call("preventDefault", []) |> ignore
          dirty.set_current(Some(false))
          set_draft(None)
          (input.clear_error)()
        }
      }),
    },
    [],
  )
}

///|
fn surface_inspector(input : SurfaceInspectorView) -> @react.Element {
  let value = input.definition
  let (error, set_error) = @react.use_state("")
  let apply = fn(patch : @core.Any) {
    attempt(
      fn() {
        input.controller.update({ "surface": patch })
        set_error("")
      },
      set_error,
      "曲面を変更できませんでした。",
    )
  }
  let scalar = fn(key : String, v : Double) {
    apply(host_record(Map([(key, @core.any(v))])))
  }
  let content : Array[&@react.ReactNode] = []
  content.push(
    component(field, { "label": @core.any("Example") }, [
      select_input(
        "Surface example",
        "",
        fn(selected_value : String) {
          let name : String = selected_value
          if !name.is_empty() {
            apply(@boundary.write_surface(@scene.surface_preset(name)))
          }
        },
        [
          select_choice("", "例を選んで作成"),
          select_choice("wave", "波状の曲面"),
          select_choice("saddle", "鞍型"),
          select_choice("sphere", "球"),
          select_choice("torus", "トーラス"),
        ],
        disabled=!input.controller.can_edit(),
      ),
    ]),
  )
  content.push(
    component(field, { "label": @core.any("Surface kind") }, [
      select_input(
        "Surface kind",
        @scene.surface_kind_name(value.kind),
        fn(selected_value : String) {
          apply(host_record({ "kind": @core.any(selected_value) }))
        },
        [
          select_choice("heightfield", "z = f(x, y)"),
          select_choice("parametric", "x(u,v), y(u,v), z(u,v)"),
        ],
        disabled=!input.controller.can_edit(),
      ),
    ]),
  )
  for
    (name, key, current) in [
      ("X", "xExpression", value.xExpression),
      ("Y", "yExpression", value.yExpression),
      ("Z", "zExpression", value.zExpression),
    ] {
    if value.kind == @scene.Heightfield && name != "Z" {
      continue
    }
    content.push(
      component(field, { "label": @core.any(name + " =") }, [
        typed_component(
          surface_expression_component,
          {
            name,
            value: current,
            apply: fn(source, success) {
              attempt(
                fn() {
                  input.controller.update({
                    "surface": host_record(Map([(key, @core.any(source))])),
                  })
                  set_error("")
                  success()
                },
                set_error,
                "曲面を変更できませんでした。",
              )
            },
            clear_error: fn() { set_error("") },
          },
          key~,
        ),
      ]),
    )
  }
  for
    (key, label, current, minimum, maximum) in [
      ("uMin", "U minimum", value.uMin, -100000.0, 100000.0),
      ("uMax", "U maximum", value.uMax, -100000.0, 100000.0),
      ("vMin", "V minimum", value.vMin, -100000.0, 100000.0),
      ("vMax", "V maximum", value.vMax, -100000.0, 100000.0),
      ("a", "Parameter a", value.a, -100000.0, 100000.0),
      ("b", "Parameter b", value.b, -100000.0, 100000.0),
      ("c", "Parameter c", value.c, -100000.0, 100000.0),
      ("yaw", "Yaw", value.yaw, -100000.0, 100000.0),
      ("pitch", "Pitch", value.pitch, -89.0, 89.0),
      ("zoom", "Zoom", value.zoom, 0.05, 10.0),
    ] {
    content.push(
      number_field(
        label,
        "Surface " + label,
        current,
        fn(v) { scalar(key, v) },
        min=minimum,
        max=maximum,
      ),
    )
  }
  content.push(
    number_field(
      "Grid divisions",
      "Surface grid divisions",
      value.steps.to_double(),
      fn(v) { apply(host_record({ "steps": @core.any(v.round().to_int()) })) },
      min=4.0,
      max=48.0,
    ),
  )
  for
    (key, label, current) in [
      ("filled", "Filled faces", value.filled),
      ("wireframe", "Wireframe", value.wireframe),
      ("axes", "Show axes", value.axes),
    ] {
    content.push(
      h("label", { "className": @core.any("check-row") }, [
        h(
          "input",
          {
            "type": @core.any("checkbox"),
            "aria-label": @core.any("Surface " + label),
            "checked": @core.any(current),
            "onChange": @core.any(fn(e : @core.Any) {
              apply(host_record(Map([(key, e._get("target")._get("checked"))])))
            }),
          },
          [],
        ),
        label,
      ]),
    )
  }
  let geometry = @render.surface_geometry(
    {
      ..@scene.default_state(@scene.Surface),
      surface: Some(value),
      width: input.width,
      height: input.height,
      fill: input.fill,
    },
    1.0,
  )
  content.push(
    h(
      "p",
      {
        "className": @core.any("muted small"),
        "data-testid": @core.any("surface-sampling"),
      },
      [
        if geometry.limited {
          "未定義・不連続付近の領域を省略しました。範囲や分割数を調整してください。"
        } else {
          "数値近似 · 細部は分割数で調整"
        },
      ],
    ),
  )
  if !error.is_empty() {
    content.push(
      h(
        "p",
        {
          "role": @core.any("alert"),
          "className": @core.any("error-text small"),
        },
        [error],
      ),
    )
  }
  inspector_section("3D surface", content)
}
