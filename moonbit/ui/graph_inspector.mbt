///|
priv struct GraphInspectorView {
  controller : InspectorController
  definition : @scene.GraphDefinition
  width : Double
  height : Double
}

///|
let graph_inspector_component : TypedComponent[GraphInspectorView] = memo_typed_component(
  graph_inspector,
)

///|
fn graph_inspector(input : GraphInspectorView) -> @react.Element {
  let graph = input.definition
  let controller = input.controller
  let (draft, set_draft) = @react.use_state((None : String?))
  let (break_draft, set_break_draft) = @react.use_state((None : String?))
  let dirty = @react.use_ref(Some(false))
  let breaks_dirty = @react.use_ref(Some(false))
  let (error, set_error) = @react.use_state("")
  let apply = fn(patch : Map[String, @core.Any]) {
    attempt(
      fn() {
        controller.update({ "graph": host_record(patch) })
        set_error("")
      },
      set_error,
      "グラフを変更できませんでした。",
    )
  }
  let scalar = fn(key : String, value : Double) {
    apply(Map([(key, @core.any(value))]))
  }
  let range = fn(
    label : String,
    low : String,
    high : String,
    low_value : Double,
    high_value : Double,
  ) -> @react.Element {
    h("div", { "className": @core.any("property-grid") }, [
      number_field(
        label + " min",
        "Graph " + label + " minimum",
        low_value,
        fn(value) { scalar(low, value) },
        min=-100000.0,
        max=100000.0,
      ),
      number_field(
        label + " max",
        "Graph " + label + " maximum",
        high_value,
        fn(value) { scalar(high, value) },
        min=-100000.0,
        max=100000.0,
      ),
    ])
  }
  let expression = h(
    "input",
    {
      "aria-label": @core.any("Graph expression"),
      "className": @core.any("content-input"),
      "spellCheck": @core.any(false),
      "value": @core.any(draft.unwrap_or(graph.expression)),
      "onFocus": @core.any(fn() { dirty.set_current(Some(false)) }),
      "onChange": @core.any(fn(event : @core.Any) {
        dirty.set_current(Some(true))
        set_draft(Some(event._get("target")._get("value").cast()))
        set_error("")
      }),
      "onBlur": @core.any(fn(event : @core.Any) {
        if dirty.get_current() == Some(true) {
          let expression : String = event
            ._get("currentTarget")
            ._get("value")
            .cast()
          if @scene.graph_validation_error({ ..graph, expression, })
            is Some(message) {
            set_error(message)
            return
          }
          apply({ "expression": @core.any(expression) })
        }
        dirty.set_current(Some(false))
        set_draft(None)
      }),
      "onKeyDown": @core.any(fn(event : @core.Any) {
        let key : String = event._get("key").cast()
        if key == "Escape" {
          dirty.set_current(Some(false))
          set_draft(None)
          set_error("")
          blur(event)
        }
        if key == "Enter" {
          blur(event)
        }
      }),
    },
    [],
  )
  let content : Array[&@react.ReactNode] = [
    component(field, { "label": @core.any("y =") }, [expression]),
    h("p", { "className": @core.any("muted small") }, [
      "x・a・b・c、pi、sin(x)、sqrt(x)、ln(x) など。Enter で反映。",
    ]),
    h("div", { "className": @core.any("property-grid") }, [
      number_field(
        "a",
        "Graph parameter a",
        graph.a,
        fn(value) { scalar("a", value) },
        min=-100000.0,
        max=100000.0,
      ),
      number_field(
        "b",
        "Graph parameter b",
        graph.b,
        fn(value) { scalar("b", value) },
        min=-100000.0,
        max=100000.0,
      ),
      number_field(
        "c",
        "Graph parameter c",
        graph.c,
        fn(value) { scalar("c", value) },
        min=-100000.0,
        max=100000.0,
      ),
    ]),
    range("X", "xMin", "xMax", graph.xMin, graph.xMax),
    range("Y", "yMin", "yMax", graph.yMin, graph.yMax),
  ]
  for
    (key, label, checked) in [
      ("axes", "Show axes", graph.axes),
      ("grid", "Show grid", graph.grid),
    ] {
    content.push(
      h("label", { "className": @core.any("muted small") }, [
        h(
          "input",
          {
            "type": @core.any("checkbox"),
            "aria-label": @core.any(label),
            "checked": @core.any(checked),
            "onChange": @core.any(fn(event : @core.Any) {
              apply(Map([(key, event._get("target")._get("checked"))]))
            }),
          },
          [],
        ),
        label,
      ]),
    )
  }
  let break_text = graph.breaks.map(fn(value) { value.to_string() }).join(", ")
  content.push(
    component(field, { "label": @core.any("Discontinuities") }, [
      h(
        "input",
        {
          "aria-label": @core.any("Graph discontinuities"),
          "value": @core.any(break_draft.unwrap_or(break_text)),
          "placeholder": @core.any("-1, 1"),
          "onFocus": @core.any(fn() { breaks_dirty.set_current(Some(false)) }),
          "onChange": @core.any(fn(event : @core.Any) {
            breaks_dirty.set_current(Some(true))
            set_break_draft(Some(event._get("target")._get("value").cast()))
          }),
          "onBlur": @core.any(fn(event : @core.Any) {
            if breaks_dirty.get_current() == Some(true) {
              let source : String = event
                ._get("currentTarget")
                ._get("value")
                .cast()
              let breaks = @scene.parse_graph_breaks(source) catch {
                @scene.InvalidGraph(message) => {
                  set_error(message)
                  return
                }
              }
              apply({
                "breaks": @core.any(
                  FixedArray::makei(breaks.length(), fn(i) { breaks[i] }),
                ),
              })
            }
            breaks_dirty.set_current(Some(false))
            set_break_draft(None)
          }),
          "onKeyDown": @core.any(fn(event : @core.Any) {
            let key : String = event._get("key").cast()
            if key == "Escape" {
              breaks_dirty.set_current(Some(false))
              set_break_draft(None)
              set_error("")
              blur(event)
            }
            if key == "Enter" {
              blur(event)
            }
          }),
        },
        [],
      ),
    ]),
  )
  content.push(
    h("p", { "className": @core.any("muted small") }, [
      "不連続になる x の値をカンマで指定。係数の動きは Transition の Graph parameters で編集できます。",
    ]),
  )
  if @render.graph_geometry(
      {
        ..@scene.default_state(Graph),
        graph: Some(graph),
        width: input.width,
        height: input.height,
      },
      1.0,
    ).limited {
    content.push(
      h(
        "p",
        { "role": @core.any("status"), "className": @core.any("muted small") },
        [
          "描画の細分化上限に達しました。範囲を狭めるか、不連続点を指定してください。",
        ],
      ),
    )
  }
  let message = if error.is_empty() {
    @scene.graph_value_error(graph).unwrap_or("")
  } else {
    error
  }
  if !message.is_empty() {
    content.push(
      h(
        "p",
        {
          "role": @core.any("alert"),
          "className": @core.any("property-timing-error"),
        },
        [message],
      ),
    )
  }
  inspector_section("Function graph", content)
}
