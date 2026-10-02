///|
priv struct CanvasSettingsView {
  size : @exporting.Size
  change : (Double?, Double?) -> Unit
  swap : () -> Unit
}

///|
fn canvas_ratio(size : @exporting.Size) -> String {
  let width = size.width.to_int()
  let height = size.height.to_int()
  let mut a = width
  let mut b = height
  while b != 0 {
    let next = a % b
    a = b
    b = next
  }
  if a <= 0 {
    ""
  } else {
    "\{width / a}:\{height / a}"
  }
}

///|
let canvas_settings_component : TypedComponent[CanvasSettingsView] = memo_typed_component(
  render_canvas_settings,
)

///|
fn render_canvas_settings(view : CanvasSettingsView) -> @react.Element {
  let presets : Array[(String, @exporting.Size)] = [
    ("16:9", { width: 1280.0, height: 720.0, }),
    ("9:16", { width: 720.0, height: 1280.0, }),
    ("1:1", { width: 1080.0, height: 1080.0, }),
    ("4:5", { width: 1080.0, height: 1350.0, }),
    ("4:3", { width: 1024.0, height: 768.0, }),
  ]
  let chosen = presets
    .iter()
    .find_first(fn(preset) {
      preset.1.width == view.size.width && preset.1.height == view.size.height
    })
    .map(fn(preset) { preset.0 })
    .unwrap_or("custom")
  let options : Array[&@react.ReactNode] = [
    export_choice("custom", "Custom", disabled=true),
  ]
  for (name, size) in presets {
    options.push(
      export_choice(name, "\{name} · \{size.width} × \{size.height}"),
    )
  }
  h("div", { "className": @core.any("canvas-settings") }, [
    component(field, { "label": @core.any("Preset") }, [
      h(
        "select",
        {
          "aria-label": @core.any("Canvas preset"),
          "value": @core.any(chosen),
          "onChange": @core.any(fn(event : @core.Any) {
            let name : String = event._get("target")._get("value").cast()
            if presets.iter().find_first(fn(preset) { preset.0 == name })
              is Some((_, size)) {
              (view.change)(Some(size.width), Some(size.height))
            }
          }),
        },
        options,
      ),
    ]),
    h("div", { "className": @core.any("property-grid") }, [
      number_field(
        "W",
        "Canvas width",
        view.size.width,
        fn(value) { (view.change)(Some(round_number(value)), None) },
        min=1.0,
        max=8192.0,
        suffix="px",
      ),
      number_field(
        "H",
        "Canvas height",
        view.size.height,
        fn(value) { (view.change)(None, Some(round_number(value))) },
        min=1.0,
        max=8192.0,
        suffix="px",
      ),
    ]),
    h("div", { "className": @core.any("canvas-dimensions") }, [
      h("span", Map([]), [canvas_ratio(view.size)]),
      h(
        "button",
        {
          "className": @core.any("text-button"),
          "onClick": @core.any(view.swap),
        },
        ["幅と高さを入れ替え"],
      ),
    ]),
    h("p", { "className": @core.any("muted small") }, [
      "配置と動きを保ったまま、Scene 全体のキャンバスを変更します。",
    ]),
  ])
}
