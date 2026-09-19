///|
extern "js" fn document_visible() -> Bool =
  #|() => !document.hidden

///|
extern "js" fn visibility_listener(callback : () -> Unit) -> () -> Unit =
  #|callback => { document.addEventListener('visibilitychange', callback); return () => document.removeEventListener('visibilitychange', callback); }

///|
extern "js" fn observe_intersection(
  node : @core.Any,
  callback : (Bool) -> Unit,
) -> () -> Unit =
  #|(node, callback) => { const observer = new IntersectionObserver(entries => callback(entries[0].isIntersecting), {root: node.closest('.assistant-messages')}); observer.observe(node); return () => observer.disconnect(); }

///|
pub fn chat_thinking(input : @core.Any) -> @react.Element {
  let active : Bool = input._get("active").cast()
  let author : String = input._get("authorName").cast()
  let element = @react.use_ref((None : @core.Any?))
  let (in_view, set_in_view) = @react.use_state(false)
  let (page_visible, set_page_visible) = @react.use_state_lazy(document_visible)
  @react.use_effect(
    fn() {
      if active && element.get_current() is Some(node) {
        let visibility = fn() { set_page_visible(document_visible()) }
        visibility()
        let disconnect = observe_intersection(node, set_in_view)
        let unsubscribe = visibility_listener(visibility)
        fn() {
          disconnect()
          unsubscribe()
        }
      } else {
        fn() { () }
      }
    },
    [@core.any(active)],
  )
  let nodes : Array[&@react.ReactNode] = [
    h(
      "span",
      {
        "className": @core.any("assistant-thinking-icon"),
        "aria-hidden": @core.any("true"),
      },
      [icon("Sparkles", 15)],
    ),
    h("div", { "className": @core.any("assistant-thinking-copy") }, [
      h("strong", Map([]), ["Codex"]),
      h("span", Map([]), [
        "考えています",
        h("span", { "className": @core.any("sr-only") }, ["…"]),
        h(
          "span",
          {
            "className": @core.any("assistant-thinking-dots"),
            "aria-hidden": @core.any("true"),
          },
          [
            h("i", { "className": @core.any("assistant-thinking-dot") }, []),
            h("i", { "className": @core.any("assistant-thinking-dot") }, []),
            h("i", { "className": @core.any("assistant-thinking-dot") }, []),
          ],
        ),
      ]),
    ]),
  ]
  if truthy(input._get("onStop")) {
    nodes.push(
      h(
        "button",
        { "type": @core.any("button"), "onClick": input._get("onStop") },
        ["停止"],
      ),
    )
  }
  h(
    "div",
    {
      "ref": element.as_any(),
      "className": @core.any("assistant-thinking"),
      "data-animate": @core.any(active && in_view && page_visible),
      "role": @core.any("status"),
      "aria-label": @core.any(
        "Codex が考えています · " + author + " の依頼",
      ),
    },
    nodes,
  )
}
