///|
priv struct TexSelection {
  key : String
  index : Int
}

///|
pub fn tex_textarea(input : @core.Any) -> @react.Element {
  let value : String = input._get("value").cast()
  let id = @react.use_id()
  let textarea = @react.use_ref((None : @core.Any?))
  let pending = @react.use_ref((None : @editor.TexInsertion?))
  let (caret, set_caret) = @react.use_state((None : Int?))
  let (active, set_active) = @react.use_state(TexSelection::{
    key: "",
    index: 0,
  })
  let (dismissed, set_dismissed) = @react.use_state("")
  let context = match caret {
    Some(position) => @editor.tex_context(value, position)
    None => None
  }
  let key = context
    .map(fn(value) { "\{value.start}:\{value.query}" })
    .unwrap_or("")
  let items = context
    .map(fn(value) { @editor.match_tex_completions(value.query, 8) })
    .unwrap_or([])
  let complete = items.length() == 1 &&
    context
    .map(fn(value) { items[0].insert == "\\" + value.query })
    .unwrap_or(false)
  let open = !items.is_empty() && key != dismissed && !complete
  let selected = if active.key == key {
    active.index.min(items.length() - 1)
  } else {
    0
  }
  @react.use_layout_effect(
    fn() {
      if pending.get_current() is Some(target) &&
        textarea.get_current() is Some(element) &&
        element._get("value").cast() == target.text {
        pending.set_current(None)
        element._call("setSelectionRange", [
          @core.any(target.caret),
          @core.any(target.caret),
        ])
        |> ignore
        set_caret(Some(target.caret))
      }
      fn() { () }
    },
    [@core.any(value)],
  )
  let sync = fn() {
    let document = @core.global_this()._get("document")
    set_caret(
      match textarea.get_current() {
        Some(element) =>
          if @core.equal(document._get("activeElement"), element) {
            Some(element._get("selectionStart").cast())
          } else {
            None
          }
        None => None
      },
    )
  }
  let accept = fn(item : @editor.TexCompletion) {
    if context is Some(context) && caret is Some(caret) {
      let next = @editor.apply_tex_completion(value, context.start, caret, item)
      pending.set_current(Some(next))
      set_dismissed("")
      input._get("onChange")._invoke([@core.any(next.text)]) |> ignore
      if textarea.get_current() is Some(element) {
        element._call("focus", []) |> ignore
      }
    }
  }
  let props = props_except(input, [
    "value", "onChange", "onKeyDown", "onKeyUp", "onSelect", "onClick", "onFocus",
    "onBlur",
  ])
  props["ref"] = textarea.as_any()
  props["value"] = @core.any(value)
  props["aria-autocomplete"] = @core.any("list")
  props["aria-controls"] = if open {
    @core.any(id + "-list")
  } else {
    @core.undefined()
  }
  props["aria-activedescendant"] = if open {
    @core.any("\{id}-\{selected}")
  } else {
    @core.undefined()
  }
  props["onChange"] = @core.any(fn(event : @core.Any) {
    pending.set_current(None)
    input._get("onChange")._invoke([event._get("target")._get("value")])
    |> ignore
    set_caret(Some(event._get("target")._get("selectionStart").cast()))
  })
  props["onKeyDown"] = @core.any(fn(event : @core.Any) {
    let handler = input._get("onKeyDown")
    if truthy(handler) {
      handler._invoke([event]) |> ignore
    }
    if !open ||
      truthy(event._get("defaultPrevented")) ||
      truthy(event._get("nativeEvent")._get("isComposing")) {
      return
    }
    let pressed : String = event._get("key").cast()
    match pressed {
      "ArrowDown" | "ArrowUp" => {
        prevent_default(event)
        set_active({
          key,
          index: (
            selected +
            (if pressed == "ArrowDown" { 1 } else { items.length() - 1 })
          ) %
          items.length(),
        })
      }
      "Enter" | "Tab" => {
        prevent_default(event)
        accept(items[selected])
      }
      "Escape" => {
        prevent_default(event)
        event._call("stopPropagation", []) |> ignore
        set_dismissed(key)
      }
      _ => ()
    }
  })
  for name in ["onKeyUp", "onSelect", "onClick", "onFocus"] {
    props[name] = @core.any(fn(event : @core.Any) {
      let handler = input._get(name)
      if truthy(handler) {
        handler._invoke([event]) |> ignore
      }
      sync()
    })
  }
  props["onBlur"] = @core.any(fn(event : @core.Any) {
    let handler = input._get("onBlur")
    if truthy(handler) {
      handler._invoke([event]) |> ignore
    }
    set_caret(None)
  })
  let nodes : Array[&@react.ReactNode] = [h("textarea", props, [])]
  if open {
    let options : Array[&@react.ReactNode] = []
    for index, item in items {
      let content : Array[&@react.ReactNode] = [
        h("code", Map([]), [item.label]),
      ]
      if item.hint is Some(hint) {
        content.push(h("span", Map([]), [hint]))
      }
      options.push(
        h(
          "li",
          {
            "key": @core.any(item.label),
            "id": @core.any("\{id}-\{index}"),
            "role": @core.any("option"),
            "aria-selected": @core.any(index == selected),
            "className": if index == selected {
              @core.any("active")
            } else {
              @core.undefined()
            },
            "onMouseDown": @core.any(prevent_default),
            "onClick": @core.any(fn() { accept(item) }),
            "onMouseEnter": @core.any(fn() { set_active({ key, index, }) }),
          },
          content,
        ),
      )
    }
    nodes.push(
      h(
        "ul",
        {
          "className": @core.any("tex-completions"),
          "id": @core.any(id + "-list"),
          "role": @core.any("listbox"),
          "aria-label": @core.any("LaTeX の候補"),
        },
        options,
      ),
    )
  }
  h("div", { "className": @core.any("tex-input") }, nodes)
}
