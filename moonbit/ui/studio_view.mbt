///|
fn studio_div(
  class_name : String,
  nodes : Array[&@react.ReactNode],
) -> @react.Element {
  h("div", { "className": @core.any(class_name) }, nodes)
}

///|
fn studio_icon_button(
  label : String,
  name : String,
  size : Int,
  click : () -> Unit,
  extra? : Map[String, @core.Any] = Map([]),
  icon_props? : Map[String, @core.Any] = Map([]),
) -> @react.Element {
  let props = extra.copy()
  props["label"] = @core.any(label)
  props["onClick"] = @core.any(click)
  component(icon_button, props, [icon(name, size, props=icon_props)])
}

///|
fn studio_avatar(name : String) -> String {
  if name.has_prefix("Guest ") {
    name[(name.length() - 2).max(0):].to_owned()
  } else {
    name[:name.length().min(2)].to_owned().to_upper()
  }
}

///|
fn studio_rail(controller : StudioController) -> @react.Element {
  let state = controller.state
  let store = controller.input._get("store")
  h(
    "nav",
    {
      "className": @core.any("app-rail"),
      "aria-label": @core.any("メインナビゲーション"),
    },
    [
      h(
        "button",
        {
          "className": @core.any("brand"),
          "aria-label": @core.any("プロジェクトを開く"),
          "title": @core.any("プロジェクトを開く"),
          "aria-haspopup": @core.any("dialog"),
          "onClick": @core.any(fn() {
            controller.update({ ..controller.state, project_open: true, })
          }),
        },
        [
          h("img", { "src": @core.any("/poietra.svg"), "alt": @core.any("") }, []),
        ],
      ),
      studio_div("rail-actions", [
        studio_icon_button(
          "Editor",
          "BookOpen",
          21,
          fn() {
            controller.update({ ..controller.state, panel: DesignPanel, })
          },
          extra={ "active": @core.any(state.panel == DesignPanel) },
        ),
        studio_icon_button(
          "共同編集チャット",
          "MessageCircle",
          21,
          fn() { controller.update({ ..controller.state, panel: ChatPanel, }) },
          extra={ "active": @core.any(state.panel == ChatPanel) },
        ),
      ]),
      studio_div("rail-bottom", [
        studio_icon_button(
          "キーボードショートカット",
          "Keyboard",
          17,
          fn() {
            controller.update({ ..controller.state, shortcuts_open: true, })
          },
        ),
        h(
          "button",
          {
            "className": @core.any("avatar own-avatar"),
            "style": host_record({ "background": store._get("color") }),
            "aria-label": @core.any("共同編集の表示名と共有"),
            "title": @core.any("共同編集の表示名と共有"),
            "onClick": @core.any(fn() {
              controller.update({ ..controller.state, share_open: true, })
            }),
          },
          [studio_avatar(store._get("userName").cast())],
        ),
      ]),
    ],
  )
}

///|
fn studio_header(
  controller : StudioController,
  snapshot : @core.Any,
  participants : Array[@core.Any],
) -> @react.Element {
  let doc = controller.document
  let store = controller.input._get("store")
  let avatars : Array[&@react.ReactNode] = []
  for index = 0; index < participants.length().min(4); index = index + 1 {
    let peer = participants[index]
    let name : String = peer._get("name").cast()
    let mine = @core.equal(
      peer._get("clientId"),
      store._get("doc")._get("clientID"),
    )
    avatars.push(
      h(
        "button",
        {
          "key": peer._get("clientId"),
          "className": @core.any("avatar"),
          "style": host_record({ "background": peer._get("color") }),
          "title": @core.any(name + (if mine { "（あなた）" } else { "" })),
          "onClick": @core.any(fn() {
            controller.update({ ..controller.state, share_open: true, })
          }),
        },
        [studio_avatar(name)],
      ),
    )
  }
  h("header", { "className": @core.any("topbar") }, [
    component(
      scene_tabs,
      {
        "project": doc.project,
        "sceneId": @core.any(doc.scene_id),
        "store": store,
        "onChange": @core.any(fn(id : String) { controller.change_scene(id) }),
        "onNew": @core.any(fn() { controller.new_scene() }),
        "notify": @core.any(fn(value : String) { controller.notify(value) }),
      },
      [],
    ),
    studio_div("topbar-spacer", []),
    studio_div("history-actions", [
      studio_icon_button(
        "元に戻す (⌘Z)",
        "Undo2",
        15,
        fn() { controller.undo() },
        extra={ "disabled": @core.any(!truthy(snapshot._get("canUndo"))) },
      ),
      studio_icon_button(
        "やり直す (⌘⇧Z)",
        "Redo2",
        15,
        fn() { controller.redo() },
        extra={ "disabled": @core.any(!truthy(snapshot._get("canRedo"))) },
      ),
    ]),
    component(
      connection_status,
      { "snapshot": snapshot, "onRetry": store._get("retryConnection") },
      [],
    ),
    studio_div("participant-stack", avatars),
    h(
      "button",
      {
        "className": @core.any("subtle-button share-button"),
        "onClick": @core.any(fn() {
          controller.update({ ..controller.state, share_open: true, })
        }),
      },
      [icon("Share2", 14), h("span", Map([]), ["Share"])],
    ),
    h(
      "button",
      {
        "className": @core.any("subtle-button"),
        "aria-label": @core.any("Preview project"),
        "onClick": @core.any(fn() {
          controller.stop()
          controller.update({ ..controller.state, preview_open: true, })
        }),
      },
      [icon("Play", 14), h("span", Map([]), ["Preview"])],
    ),
    h(
      "button",
      {
        "className": @core.any("primary-button export-button"),
        "onClick": @core.any(fn() {
          controller.update({ ..controller.state, export_open: true, })
        }),
        "disabled": @core.any(!truthy(controller.input._get("exporter"))),
      },
      [icon("Film", 14), h("span", Map([]), ["Export"])],
    ),
  ])
}

///|
fn studio_aside(
  controller : StudioController,
  chat : FixedArray[@core.Any],
  panel : @react.ReactRef[@core.Any],
) -> @react.Element {
  let state = controller.state
  let doc = controller.document
  let mut after = state.last_read is None
  let mut found = false
  let mut unread = 0
  for message in chat {
    if state.last_read == Some(message._get("id").cast()) {
      after = true
      found = true
      continue
    }
    if after &&
      (
        !@core.equal(
          message._get("authorId"),
          controller.input._get("store")._get("chatAuthorId"),
        ) ||
        @core.equal(message._get("role"), @core.any("assistant"))
      ) {
      unread += 1
    }
  }
  if state.last_read is Some(_) && !found {
    unread = chat
      .iter()
      .filter(fn(message) {
        !@core.equal(
          message._get("authorId"),
          controller.input._get("store")._get("chatAuthorId"),
        ) ||
        @core.equal(message._get("role"), @core.any("assistant"))
      })
      .count()
  }
  let chat_label : Array[&@react.ReactNode] = [
    icon("MessageCircle", 13),
    "Chat",
  ]
  if unread > 0 {
    chat_label.push(
      h(
        "span",
        {
          "className": @core.any("chat-unread"),
          "aria-label": @core.any("\{unread} 件の未読"),
        },
        ["\{unread.min(99)}"],
      ),
    )
  }
  let nodes : Array[&@react.ReactNode] = [
    studio_div("inspector-tabs", [
      h(
        "button",
        {
          "className": @core.any(
            if state.panel == DesignPanel {
              "selected"
            } else {
              ""
            },
          ),
          "onClick": @core.any(fn() {
            controller.update({ ..controller.state, panel: DesignPanel, })
          }),
        },
        [icon("SlidersHorizontal", 13), "Design"],
      ),
      h(
        "button",
        {
          "className": @core.any(
            if state.panel == ChatPanel {
              "selected"
            } else {
              ""
            },
          ),
          "aria-label": @core.any("Chat"),
          "onClick": @core.any(fn() {
            controller.update({ ..controller.state, panel: ChatPanel, })
          }),
        },
        chat_label,
      ),
    ]),
  ]
  if state.panel == DesignPanel {
    nodes.push(
      if state.viewing() {
        component(
          playback_panel,
          {
            "key": @core.any("playback"),
            "scene": doc.scene,
            "segment": doc.at_time,
            "playhead": @core.any(state.playhead),
            "onEdit": @core.any(fn() { controller.edit_moment(false) }),
          },
          [],
        )
      } else {
        component(inspector, { "key": @core.any("inspector") }, [])
      },
    )
  }
  nodes.push(
    h(
      "div",
      {
        "key": @core.any("assistant"),
        "className": @core.any("assistant-tab-content"),
        "hidden": @core.any(state.panel != ChatPanel),
      },
      [
        component(
          assistant_panel,
          {
            "isActive": @core.any(
              state.panel == ChatPanel && !state.preview_open,
            ),
            "onOpenScene": @core.any(fn(id : String) {
              controller.change_scene(id)
            }),
            "onEditMoment": @core.any(fn() { controller.edit_moment(false) }),
          },
          [],
        ),
      ],
    ),
  )
  h(
    "aside",
    { "ref": panel.as_any(), "className": @core.any("right-panel") },
    nodes,
  )
}

///|
fn studio_view(
  controller : StudioController,
  snapshot : @core.Any,
  chat : FixedArray[@core.Any],
  imports : @core.Any,
  frames : StudioFrames,
  panel : @react.ReactRef[@core.Any],
  image_input : @react.ReactRef[@core.Any],
  media_input : @react.ReactRef[@core.Any],
) -> @react.Element {
  let doc = controller.document
  let store = controller.input._get("store")
  let peers : FixedArray[@core.Any] = snapshot._get("peers").cast()
  let participants = Array::makei(peers.length(), fn(i) { peers[i] })
  participants.sort_by(fn(a, b) {
    if @core.equal(a._get("clientId"), store._get("doc")._get("clientID")) {
      -1
    } else if @core.equal(
        b._get("clientId"),
        store._get("doc")._get("clientID"),
      ) {
      1
    } else {
      let a : Double = a._get("clientId").cast()
      let b : Double = b._get("clientId").cast()
      a.compare(b)
    }
  })
  let nodes : Array[&@react.ReactNode] = [
    studio_rail(controller),
    studio_div("project-heading", [
      h(
        "input",
        {
          "aria-label": @core.any("Project name"),
          "value": doc.project._get("name"),
          "onChange": @core.any(fn(event : @core.Any) {
            store._call("setProjectName", [event._get("target")._get("value")])
            |> ignore
          }),
        },
        [],
      ),
    ]),
    studio_header(controller, snapshot, participants),
    component(
      sidebar,
      Map([("onNewScene", @core.any(fn() { controller.new_scene() }))]),
      [],
    ),
    studio_main(controller, imports, frames, image_input, media_input),
    studio_aside(controller, chat, panel),
  ]
  if !controller.state.toast.is_empty() {
    nodes.push(
      h(
        "div",
        {
          "key": @core.any("toast"),
          "className": @core.any("toast"),
          "role": @core.any("status"),
        },
        [icon("Check", 15), controller.state.toast],
      ),
    )
  }
  nodes.append(studio_dialogs(controller, snapshot, participants))
  h(
    "div",
    { "className": @core.any("studio"), "data-engine": @core.any("wasm") },
    nodes,
  )
}
