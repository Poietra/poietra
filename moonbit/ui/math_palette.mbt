///|
fn math_palette(input : @core.Any) -> @react.Element {
  let controller : StudioController = input._get("controller").cast()
  let (query, set_query) = @react.use_state("")
  let needle = @editor.trim_text(query).to_owned().to_lower()
  let nodes : Array[&@react.ReactNode] = [
    h(
      "input",
      {
        "aria-label": @core.any("数学の表現を検索"),
        "type": @core.any("search"),
        "className": @core.any("content-input"),
        "placeholder": @core.any(
          "数式、ベクトル、グラフ理論、3D…",
        ),
        "value": @core.any(query),
        "onChange": @core.any(fn(event : @core.Any) {
          set_query(event._get("target")._get("value").cast())
        }),
      },
      [],
    ),
  ]
  let items = @editor.math_tools().filter(fn(item) {
    (item.category + item.label + item.description).to_lower().contains(needle)
  })
  for item in items {
    nodes.push(
      h(
        "button",
        {
          "key": @core.any(@scene.object_kind_name(item.kind)),
          "className": @core.any("math-tool-option"),
          "aria-label": @core.any(item.label),
          "onClick": @core.any(fn() {
            controller.update({ ..controller.state, math_open: false, })
            controller.activate(@editor.DrawTool(item.kind))
          }),
        },
        [
          icon(item.icon, 20),
          h("span", Map([]), [
            h("span", { "className": @core.any("muted small") }, [item.category]),
            h("strong", Map([]), [item.label]),
            h("span", { "className": @core.any("muted small") }, [
              item.description,
            ]),
          ]),
        ],
      ),
    )
  }
  if items.is_empty() {
    nodes.push(
      h("p", { "className": @core.any("muted") }, [
        "該当する表現がありません。別の言葉で検索してください。",
      ]),
    )
  }
  component(
    modal,
    {
      "open": @core.any(controller.state.math_open),
      "title": @core.any("数学の表現を追加"),
      "onOpenChange": @core.any(fn(value : Bool) {
        controller.update({ ..controller.state, math_open: value, })
      }),
    },
    [h("div", { "className": @core.any("math-tools") }, nodes)],
  )
}
