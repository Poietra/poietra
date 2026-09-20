///|
fn studio_share_dialog(
  controller : StudioController,
  participants : Array[@core.Any],
) -> @react.Element {
  let state = controller.state
  let store = controller.input._get("store")
  let peers : Array[&@react.ReactNode] = [
    h("h3", Map([]), [
      "In this project ",
      h("span", Map([]), ["\{participants.length()}"]),
    ]),
  ]
  for peer in participants {
    let name : String = peer._get("name").cast()
    peers.push(
      h("div", { "key": peer._get("clientId") }, [
        h(
          "span",
          {
            "className": @core.any("avatar"),
            "style": host_record({ "background": peer._get("color") }),
          },
          [name[(name.length() - 2).max(0):].to_owned().to_upper()],
        ),
        h("span", Map([]), [name]),
        h("small", Map([]), [
          if @core.equal(
              peer._get("clientId"),
              store._get("doc")._get("clientID"),
            ) {
            "You"
          } else {
            "Editing"
          },
        ]),
      ]),
    )
  }
  component(
    modal,
    {
      "key": @core.any("share"),
      "open": @core.any(state.share_open),
      "onOpenChange": @core.any(fn(value : Bool) {
        controller.update({ ..controller.state, share_open: value, })
      }),
      "title": @core.any("A little better, together."),
      "description": @core.any(
        "同じリンクを開けば、このプロジェクトを一緒に編集できます。",
      ),
    },
    [
      studio_div("share-link", [
        h(
          "input",
          {
            "aria-label": @core.any("共有リンク"),
            "readOnly": @core.any(true),
            "value": @core.global_this()._get("location")._get("href"),
            "onFocus": @core.any(fn(event : @core.Any) {
              event._get("currentTarget")._call("select", []) |> ignore
            }),
          },
          [],
        ),
        h(
          "button",
          {
            "className": @core.any("primary-button"),
            "onClick": @core.any(fn() { controller.share() }),
          },
          [
            icon(if state.copied { "Check" } else { "Copy" }, 14),
            h("span", Map([]), [
              if state.copied {
                "Copied"
              } else {
                "Copy link"
              },
            ]),
          ],
        ),
      ]),
      studio_div("share-participants", peers),
      h("label", { "className": @core.any("name-field") }, [
        "共同編集での表示名",
        h(
          "input",
          {
            "value": @core.any(state.user_name),
            "aria-describedby": @core.any("collaboration-name-hint"),
            "maxLength": @core.any(40),
            "onChange": @core.any(fn(event : @core.Any) {
              controller.update({
                ..controller.state,
                user_name: event._get("target")._get("value").cast(),
              })
            }),
            "onBlur": @core.any(fn() {
              store._call("setName", [@core.any(controller.state.user_name)])
              |> ignore
              controller.update({
                ..controller.state,
                user_name: store._get("userName").cast(),
              })
            }),
          },
          [],
        ),
      ]),
      h(
        "p",
        {
          "id": @core.any("collaboration-name-hint"),
          "className": @core.any("account-hint"),
        },
        [
          "参加者やチャットに表示する名前です。このブラウザに保存され、ログイン先の名前とは別に変更できます。",
        ],
      ),
      studio_div("share-footer", [
        h("span", Map([]), [
          icon("Link2", 12),
          "リンクを知っている人が編集できます",
        ]),
        h(
          "button",
          {
            "className": @core.any("text-button"),
            "disabled": @core.any(state.saving),
            "onClick": @core.any(fn() { controller.save_project() }),
          },
          [icon("Download", 13), "Save project"],
        ),
      ]),
    ],
  )
}

///|
fn studio_shortcuts(controller : StudioController) -> @react.Element {
  let nodes : Array[&@react.ReactNode] = []
  for
    (key, action) in [
      ("Space", "再生 / 停止"),
      ("V / R / O / P", "選択 / 四角 / 円 / パス"),
      ("Drag / Shift + click", "範囲選択 / 追加選択"),
      ("↑ ↓ ← → / Shift", "1 px / 10 px 移動"),
      ("⌘ / Ctrl + C / X / V", "コピー / 切り取り / 貼り付け"),
      ("⌘ / Ctrl + ⇧V", "同じ位置に貼り付け"),
      ("⌘ / Ctrl + D", "複製"),
      ("⌘ / Ctrl + G / ⇧G", "Group / Ungroup"),
      ("⌘ / Ctrl + Z", "元に戻す"),
      ("Delete", "この場面から非表示"),
    ] {
    nodes.push(
      h("div", { "key": @core.any(key) }, [
        h("span", Map([]), [action]),
        h("kbd", Map([]), [key]),
      ]),
    )
  }
  component(
    modal,
    {
      "key": @core.any("shortcuts"),
      "open": @core.any(controller.state.shortcuts_open),
      "onOpenChange": @core.any(fn(value : Bool) {
        controller.update({ ..controller.state, shortcuts_open: value, })
      }),
      "title": @core.any("キーボードショートカット"),
    },
    [studio_div("keyboard-shortcuts", nodes)],
  )
}

///|
fn studio_dialogs(
  controller : StudioController,
  snapshot : @core.Any,
  participants : Array[@core.Any],
) -> Array[&@react.ReactNode] {
  let doc = controller.document
  let state = controller.state
  let input = controller.input
  let nodes : Array[&@react.ReactNode] = [
    component(
      project_dialog,
      {
        "key": @core.any("projects"),
        "open": @core.any(state.project_open),
        "onOpenChange": @core.any(fn(value : Bool) {
          controller.update({ ..controller.state, project_open: value, })
        }),
        "project": doc.project,
        "roomId": input._get("store")._get("roomId"),
        "synced": snapshot._get("synced"),
        "services": input._get("services"),
      },
      [],
    ),
    studio_share_dialog(controller, participants),
    studio_shortcuts(controller),
    component(
      project_preview,
      {
        "key": @core.any("project-preview"),
        "open": @core.any(state.preview_open),
        "onOpenChange": @core.any(fn(value : Bool) {
          controller.update({ ..controller.state, preview_open: value, })
        }),
        "project": doc.project,
        "renderer": input._get("renderer"),
        "kernel": input._get("kernel"),
        "createFramePainter": input._get("createFramePainter"),
        "onEdit": @core.any(fn(id : String, value : @core.Any) {
          controller.change_scene(id)
          let next = studio_selection(value)
          let scene = input._get("store")._call("scene", [@core.any(id)])
          controller.update({
            ..controller.state,
            selection: next,
            playhead: studio_segment_start(scene, next.id()),
            panel: DesignPanel,
          })
        }),
      },
      [],
    ),
  ]
  if truthy(input._get("exporter")) {
    nodes.push(
      component(
        export_dialog,
        {
          "key": @core.any("export"),
          "open": @core.any(state.export_open),
          "onOpenChange": @core.any(fn(value : Bool) {
            controller.update({ ..controller.state, export_open: value, })
          }),
          "exporter": input._get("exporter"),
          "scene": doc.scene,
          "project": doc.project,
          "kernel": input._get("kernel"),
          "name": doc.project._get("name"),
        },
        [],
      ),
    )
  }
  nodes
}
