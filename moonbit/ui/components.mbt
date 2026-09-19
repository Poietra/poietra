///|
pub fn icon_button(input : @core.Any) -> @react.Element {
  let label : String = input._get("label").cast()
  let props = props_except(input, [
    "label", "active", "className", "children", "disabled",
  ])
  props["disabled"] = input._get("disabled")
  props["render"] = @core.any(
    h("button", { "disabled": input._get("disabled") }, []),
  )
  props["aria-label"] = @core.any(label)
  props["className"] = classes([
    @core.any("icon-button"),
    @core.any(if truthy(input._get("active")) { "active" } else { "" }),
    input._get("className"),
  ])
  ui("Tooltip", "Root", Map([]), [
    ui("Tooltip", "Trigger", props, [children(input)]),
    ui("Tooltip", "Portal", Map([]), [
      ui("Tooltip", "Positioner", { "sideOffset": @core.any(7) }, [
        ui("Tooltip", "Popup", { "className": @core.any("tooltip") }, [label]),
      ]),
    ]),
  ])
}

///|
pub fn field(input : @core.Any) -> @react.Element {
  let label : String = input._get("label").cast()
  h(
    "label",
    {
      "className": classes([
        @core.any("property-field"),
        input._get("className"),
      ]),
    },
    [h("span", Map([]), [label]), children(input)],
  )
}

///|
priv enum NumberDraft {
  Idle
  Editing(String)
}

///|
pub fn number_input(input : @core.Any) -> @react.Element {
  let value : Double = input._get("value").cast()
  let on_change : (Double) -> Unit = input._get("onChange").cast()
  let low = optional_number(input, "min", -10000.0)
  let high = optional_number(input, "max", 10000.0)
  let step = optional_number(input, "step", 1.0)
  let (draft, set_draft) = @react.use_state(NumberDraft::Idle)
  let dirty = @react.use_ref(Some(false))
  let commit = fn() {
    if dirty.get_current() == Some(true) &&
      draft is Editing(text) &&
      !@editor.trim_text(text).is_empty() {
      let number = number_value(text)
      if !number.is_nan() && !number.is_inf() {
        on_change(@scene.clamp(number, low, high))
      }
    }
    dirty.set_current(Some(false))
    set_draft(Idle)
  }
  let shown = round_number(value * 100.0) / 100.0
  let props : Map[String, @core.Any] = {
    "aria-label": input._get("label"),
    "type": @core.any("number"),
    "step": @core.any(step),
    "min": @core.any(low),
    "max": @core.any(high),
    "value": match draft {
      Idle => @core.any(shown)
      Editing(text) => @core.any(text)
    },
    "onFocus": @core.any(fn() {
      dirty.set_current(Some(false))
      set_draft(Editing(string_value(@core.any(shown))))
    }),
    "onChange": @core.any(fn(event : @core.Any) {
      dirty.set_current(Some(true))
      set_draft(Editing(event._get("target")._get("value").cast()))
    }),
    "onBlur": @core.any(commit),
    "onKeyDown": @core.any(fn(event : @core.Any) {
      let key : String = event._get("key").cast()
      match key {
        "Enter" => blur(event)
        "Escape" => {
          dirty.set_current(Some(false))
          blur(event)
        }
        _ => ()
      }
    }),
  }
  let nodes : Array[&@react.ReactNode] = [h("input", props, [])]
  let suffix = input._get("suffix")
  if truthy(suffix) {
    let text : String = suffix.cast()
    nodes.push(h("span", Map([]), [text]))
  }
  h("span", { "className": @core.any("number-input") }, nodes)
}

///|
pub fn modal(input : @core.Any) -> @react.Element {
  let title : String = input._get("title").cast()
  let content : Array[&@react.ReactNode] = [
    h("div", { "className": @core.any("dialog-heading") }, [
      ui("Dialog", "Title", { "className": @core.any("text-balance") }, [title]),
      ui(
        "Dialog",
        "Close",
        {
          "className": @core.any("icon-button"),
          "aria-label": @core.any("閉じる"),
        },
        [icon("X", 17)],
      ),
    ]),
  ]
  let description = input._get("description")
  if truthy(description) {
    let text : String = description.cast()
    content.push(
      ui(
        "Dialog",
        "Description",
        { "className": @core.any("dialog-description text-pretty") },
        [text],
      ),
    )
  }
  content.push(children(input))
  ui(
    "Dialog",
    "Root",
    { "open": input._get("open"), "onOpenChange": input._get("onOpenChange") },
    [
      ui("Dialog", "Portal", Map([]), [
        ui(
          "Dialog",
          "Backdrop",
          { "className": @core.any("dialog-backdrop") },
          [],
        ),
        ui(
          "Dialog",
          "Popup",
          {
            "className": classes([@core.any("dialog"), input._get("className")]),
          },
          content,
        ),
      ]),
    ],
  )
}

///|
pub fn section(input : @core.Any) -> @react.Element {
  let title : String = input._get("title").cast()
  h("section", { "className": @core.any("property-section") }, [
    h("div", { "className": @core.any("section-heading") }, [
      h("h3", Map([]), [title]),
      HostNode::{ value: input._get("action"), },
    ]),
    children(input),
  ])
}
