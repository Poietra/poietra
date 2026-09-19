///|
fn chat_proposal_card(
  controller : ChatController,
  message : @editor.ChatMessage[@core.Any],
  target_scene : @core.Any,
) -> @react.Element {
  let proposal = message.proposal.unwrap()
  let own = message.author_id == controller.author_id
  let scene = controller.editor._get("scene")
  let targets = if truthy(target_scene) {
    @boundary.read_proposal_targets(proposal, target_scene)
  } else {
    []
  }
  let nodes : Array[&@react.ReactNode] = [
    h("span", Map([]), [string_value(proposal._get("count")) + " 件の編集"]),
  ]
  if message.applied.unwrap_or(false) {
    nodes.push(
      h("span", { "className": @core.any("applied") }, [
        icon("Check", 13),
        "Applied",
      ]),
    )
  } else if message.dismissed.unwrap_or(false) {
    nodes.push(h("span", { "className": @core.any("muted") }, ["Discarded"]))
  } else if !own {
    nodes.push(
      h("span", { "className": @core.any("muted") }, [
        "依頼した人が適用できます",
      ]),
    )
  } else if message.scope.scene_id != controller.scene_id {
    nodes.push(
      h("span", { "className": @core.any("muted") }, [
        "対象の Scene で適用できます",
      ]),
    )
  } else {
    nodes.push(
      h("div", Map([]), [
        h(
          "button",
          {
            "className": @core.any("primary-button small-button"),
            "disabled": controller.editor._get("viewingPlayback"),
            "onClick": @core.any(fn() { controller.apply(message.id, false) }),
          },
          ["Apply edits"],
        ),
        h(
          "button",
          {
            "className": @core.any("icon-button"),
            "aria-label": @core.any("編集案を破棄"),
            "onClick": @core.any(fn() {
              controller.chat._call("patch", [
                @core.any(message.id),
                host_record({ "dismissed": @core.any(true) }),
              ])
              |> ignore
            }),
          },
          [icon("X", 13)],
        ),
      ]),
    )
  }
  let rows : Array[&@react.ReactNode] = []
  for target in targets {
    let missing = target.created &&
      !chat_selection_exists(scene, target.selection)
    let key = match target.selection {
      Composition(id) => "composition:" + id
      Transition(id) => "transition:" + id
    }
    rows.push(
      h(
        "div",
        { "className": @core.any("proposal-target"), "key": @core.any(key) },
        [
          h("span", Map([]), [target.label]),
          h(
            "button",
            {
              "className": @core.any("subtle-button small-button"),
              "disabled": @core.any(
                message.scope.scene_id != controller.scene_id || missing,
              ),
              "onClick": @core.any(fn() { controller.show_target(target) }),
            },
            [if missing { "適用後に表示" } else { "対象を表示" }],
          ),
        ],
      ),
    )
  }
  nodes.push(
    h(
      "div",
      {
        "className": @core.any("proposal-targets"),
        "aria-label": @core.any("編集する対象"),
      },
      rows,
    ),
  )
  h("div", { "className": @core.any("proposal-card") }, nodes)
}

///|
fn chat_message_view(
  controller : ChatController,
  message : @editor.ChatMessage[@core.Any],
  pending : ChatRequest?,
  project : @core.Any,
) -> @react.Element {
  let own = message.author_id == controller.author_id
  let target_scene = if truthy(project) {
    project._get("scenes")._get(message.scope.scene_id)
  } else {
    @core.undefined()
  }
  let author : Array[&@react.ReactNode] = []
  if message.role == @editor.Person {
    author.push(
      h(
        "span",
        {
          "className": @core.any("chat-avatar"),
          "style": host_record({ "background": @core.any(message.color) }),
        },
        [message.author_name[:message.author_name.length().min(1)].to_owned()],
      ),
    )
    author.push(message.author_name)
    if own {
      author.push(h("small", Map([]), ["You"]))
    }
  } else {
    author.push(icon("Sparkles", 12))
    author.push("Codex")
  }
  let date = @core.new(@core.global_this()._get("Date"), [
    @core.any(message.created_at),
  ])
  author.push(
    h("time", { "dateTime": date._call("toISOString", []) }, [
      string_value(
        date._call("toLocaleTimeString", [
          @core.any(([] : FixedArray[String])),
          host_record({
            "hour": @core.any("2-digit"),
            "minute": @core.any("2-digit"),
          }),
        ]),
      ),
    ]),
  )
  let nodes : Array[&@react.ReactNode] = [
    h("div", { "className": @core.any("chat-author") }, author),
  ]
  if message.role == @editor.Person {
    nodes.push(
      h("small", { "className": @core.any("muted") }, [message.scope.label]),
    )
  }
  if message.scope.scene_id != controller.scene_id && truthy(target_scene) {
    nodes.push(
      h(
        "button",
        {
          "className": @core.any("chat-scene-link"),
          "onClick": @core.any(fn() {
            (controller.open_scene)(message.scope.scene_id)
          }),
        },
        [
          string_value(target_scene._get("name")) + " を開く",
          icon("ChevronRight", 11),
        ],
      ),
    )
  }
  nodes.push(h("p", Map([]), [message.content]))
  if message.mentions_codex.unwrap_or(false) &&
    message.status == Some(@editor.Pending) {
    let props = {
      "active": @core.any(controller.active),
      "authorName": @core.any(message.author_name),
    }
    if pending
      .map(fn(request) { request.message_id == message.id })
      .unwrap_or(false) {
      props["onStop"] = @core.any(fn() { controller.stop() })
    }
    nodes.push(component(chat_thinking, props, []))
  }
  if message.status == Some(@editor.Cancelled) {
    nodes.push(
      h("small", { "className": @core.any("muted") }, ["停止しました"]),
    )
  }
  if message.status == Some(@editor.Failed) {
    nodes.push(
      h("small", { "className": @core.any("muted") }, [
        "Codex への依頼に失敗しました",
      ]),
    )
  }
  if own &&
    message.mentions_codex.unwrap_or(false) &&
    (
      message.status == Some(@editor.Failed) ||
      message.status == Some(@editor.Cancelled)
    ) {
    nodes.push(
      h(
        "button",
        {
          "className": @core.any("chat-scene-link"),
          "onClick": @core.any(fn() {
            if message.scope.scene_id != controller.scene_id {
              (controller.open_scene)(message.scope.scene_id)
            }
            controller.drafts[message.scope.scene_id] = message.content
            if message.scope.scene_id == controller.scene_id {
              (controller.set_prompt)(message.content)
            }
            controller.focus()
          }),
        },
        ["依頼を入力欄に戻す"],
      ),
    )
  }
  if message.proposal is Some(proposal) {
    let changes : FixedArray[@core.Any] = proposal._get("changes").cast()
    if !changes.is_empty() {
      nodes.push(chat_proposal_card(controller, message, target_scene))
    }
  }
  h(
    "div",
    {
      "key": @core.any(message.id),
      "className": @core.any(
        "chat-message " +
        (if message.role == @editor.Person { "user" } else { "assistant" }),
      ),
    },
    nodes,
  )
}
