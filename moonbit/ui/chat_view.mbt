///|
fn chat_view(
  controller : ChatController,
  messages : FixedArray[@core.Any],
  pending : ChatRequest?,
  error : String,
  retry : ChatRetry?,
  new_messages : Bool,
) -> @react.Element {
  let nodes : Array[&@react.ReactNode] = []
  if messages.is_empty() {
    nodes.push(
      h(
        "div",
        {
          "className": @core.any("assistant-heading"),
          "key": @core.any("heading"),
        },
        [
          h("span", { "className": @core.any("assistant-icon") }, [
            icon("MessageCircle", 18),
          ]),
          h("div", Map([]), [
            h("h2", Map([]), ["Room chat"]),
            h("p", Map([]), [
              "みんなで相談。@codex で編集を依頼。",
            ]),
          ]),
        ],
      ),
    )
  }
  let rows : Array[&@react.ReactNode] = []
  if messages.is_empty() {
    let suggestions : Array[&@react.ReactNode] = []
    for text in chat_suggestions(controller.editor) {
      suggestions.push(
        h(
          "button",
          {
            "key": @core.any(text),
            "onClick": @core.any(fn() {
              controller.update_prompt("@codex " + text)
              controller.focus()
            }),
          },
          [h("span", Map([]), [text]), icon("ChevronRight", 13)],
        ),
      )
    }
    rows.push(
      h("div", { "className": @core.any("assistant-welcome") }, [
        h("p", Map([]), [
          "この部屋のメンバーと、制作の相談を。",
          h("br", Map([]), []),
          h("strong", Map([]), ["@codex"]),
          " で AI も会話に参加します。",
        ]),
        h("div", { "className": @core.any("prompt-suggestions") }, suggestions),
        h("small", Map([]), [
          "AI の編集案は、依頼した人が確認して適用できます。",
        ]),
      ]),
    )
  }
  let project = controller.store._call("snapshot", [])._get("project")
  for message in messages {
    rows.push(
      chat_message_view(
        controller,
        @boundary.read_chat_message(message),
        pending,
        project,
      ),
    )
  }
  nodes.push(
    h(
      "div",
      {
        "key": @core.any("messages"),
        "ref": controller.list.as_any(),
        "className": @core.any("assistant-messages"),
        "role": @core.any("log"),
        "aria-label": @core.any("共同編集チャット"),
        "aria-live": @core.any("polite"),
        "onScroll": @core.any(fn(event : @core.Any) {
          let list = event._get("currentTarget")
          controller.follow.val = (list._get("scrollHeight").cast() : Double) -
            (list._get("scrollTop").cast() : Double) -
            (list._get("clientHeight").cast() : Double) <
            40.0
          if controller.follow.val {
            (controller.set_new_messages)(false)
          }
        }),
      },
      rows,
    ),
  )
  if new_messages {
    nodes.push(
      h(
        "div",
        { "className": @core.any("assistant-jump"), "key": @core.any("latest") },
        [
          h(
            "button",
            {
              "type": @core.any("button"),
              "onClick": @core.any(fn() { controller.show_latest() }),
            },
            [icon("ArrowDown", 12), "最新のメッセージへ"],
          ),
        ],
      ),
    )
  }
  let composer : Array[&@react.ReactNode] = []
  if !error.is_empty() {
    let content : Array[&@react.ReactNode] = [error]
    if retry is Some(retry) && pending is None {
      content.push(
        h(
          "button",
          {
            "className": @core.any("text-button"),
            "onClick": @core.any(fn() {
              controller.send(retry.prompt, Some(retry.message_id), false)
            }),
          },
          ["再試行"],
        ),
      )
    }
    composer.push(
      h(
        "p",
        {
          "className": @core.any("inline-error"),
          "role": @core.any("alert"),
          "key": @core.any("error"),
        },
        content,
      ),
    )
  }
  if truthy(controller.editor._get("viewingPlayback")) {
    composer.push(
      h(
        "p",
        {
          "className": @core.any("assistant-connection"),
          "key": @core.any("playback"),
        },
        [
          "AI への依頼・適用は編集画面で。",
          h(
            "button",
            {
              "className": @core.any("text-button"),
              "onClick": @core.any(controller.edit_moment),
            },
            ["この場面を編集"],
          ),
        ],
      ),
    )
  }
  if controller.available == Some(false) && error.is_empty() {
    composer.push(
      h(
        "p",
        {
          "className": @core.any("assistant-connection"),
          "key": @core.any("connection"),
        },
        ["Codex の接続待ち · メンバーとは会話できます"],
      ),
    )
  }
  let addressing = @boundary.codex_mention(controller.prompt) is Some(_)
  composer.push(
    h(
      "form",
      {
        "key": @core.any("form"),
        "onSubmit": @core.any(fn(event : @core.Any) {
          prevent_default(event)
          controller.send(controller.prompt, None, false)
        }),
      },
      [
        h(
          "textarea",
          {
            "ref": controller.composer.as_any(),
            "aria-label": @core.any("チャットメッセージ"),
            "placeholder": @core.any(
              "メンバーに送信、@codex で AI に依頼",
            ),
            "value": @core.any(controller.prompt),
            "maxLength": @core.any(3000),
            "rows": @core.any(3),
            "onChange": @core.any(fn(event : @core.Any) {
              controller.update_prompt(
                event._get("target")._get("value").cast(),
              )
            }),
            "onKeyDown": @core.any(fn(event : @core.Any) {
              if @core.equal(event._get("key"), @core.any("Enter")) &&
                !truthy(event._get("shiftKey")) &&
                !truthy(event._get("nativeEvent")._get("isComposing")) {
                prevent_default(event)
                controller.send(
                  controller.prompt,
                  None,
                  truthy(event._get("metaKey")) || truthy(event._get("ctrlKey")),
                )
              }
            }),
          },
          [],
        ),
        h("div", { "className": @core.any("composer-bottom") }, [
          h(
            "button",
            {
              "className": @core.any("mention-button"),
              "type": @core.any("button"),
              "onClick": @core.any(fn() {
                controller.update_prompt(
                  if addressing {
                    controller.prompt
                  } else {
                    "@codex " + controller.prompt
                  },
                )
                controller.focus()
              }),
            },
            ["@codex"],
          ),
          h("span", Map([]), [
            if addressing {
              string_value(controller.editor._get("scene")._get("name"))
            } else {
              "Everyone"
            },
          ]),
          h(
            "button",
            {
              "className": @core.any("send-button"),
              "aria-label": @core.any("送信"),
              "type": @core.any("submit"),
              "disabled": @core.any(
                controller.prompt.trim().is_empty() ||
                (
                  addressing &&
                  (
                    pending is Some(_) ||
                    controller.available != Some(true) ||
                    truthy(controller.editor._get("viewingPlayback"))
                  )
                ),
              ),
            },
            [icon("ArrowUp", 17)],
          ),
        ]),
      ],
    ),
  )
  composer.push(
    h("small", { "key": @core.any("help") }, [
      "Enter で送信 · Shift + Enter で改行 · ⌘/Ctrl + Enter で @codex の編集案を即適用",
    ]),
  )
  nodes.push(
    h(
      "div",
      {
        "className": @core.any("assistant-composer"),
        "key": @core.any("composer"),
      },
      composer,
    ),
  )
  h("div", { "className": @core.any("assistant-panel") }, nodes)
}
