///|
pub fn assistant_panel(input : @core.Any) -> @react.Element {
  let state = use_editor_state()
  let peers = use_editor_peers(state)
  let editor = ui_shallow_copy(state)
  editor._set("peers", peers)
  let store = editor._get("store")
  let chat = store._get("chat")
  let scene_id : String = editor._get("scene")._get("id").cast()
  let messages : FixedArray[@core.Any] = @react.use_sync_external_store(
    chat._get("subscribe").cast(),
    chat._get("snapshot").cast(),
  )
  let (prompt, set_prompt) = @react.use_state("")
  let (pending, set_pending) = @react.use_state((None : ChatRequest?))
  let (available, set_available) = @react.use_state((None : Bool?))
  let (error, set_error) = @react.use_state("")
  let (retry, set_retry) = @react.use_state((None : ChatRetry?))
  let (new_messages, set_new_messages) = @react.use_state(false)
  let composer = @react.use_ref((None : @core.Any?))
  let list = @react.use_ref((None : @core.Any?))
  let request = @react.use_ref((None : ChatRequest?))
  let latest = @react.use_ref((None : ChatController?))
  let current_scene = @react.use_ref(Some(scene_id))
  let last_id = @react.use_ref((None : String?))
  let drafts = @react.use_ref(Some((Map([]) : Map[String, String])))
    .get_current()
    .unwrap()
  let applied = @react.use_ref(Some((Set([]) : Set[String])))
    .get_current()
    .unwrap()
  let follow = @react.use_ref(Some(Ref(true))).get_current().unwrap()
  current_scene.set_current(Some(scene_id))
  let controller : ChatController = {
    editor,
    store,
    chat,
    scene_id,
    author_id: store._get("chatAuthorId").cast(),
    prompt,
    available,
    active: input._get("isActive").cast(),
    request,
    current_scene,
    latest,
    composer,
    list,
    drafts,
    applied,
    follow,
    set_prompt,
    set_pending,
    set_error,
    set_retry,
    set_new_messages,
    open_scene: input._get("onOpenScene").cast(),
    edit_moment: input._get("onEditMoment").cast(),
  }
  latest.set_current(Some(controller))
  @react.use_effect(
    fn() {
      let active = Ref(true)
      let checking = Ref(false)
      let health = new_controller()
      let leave = fn() {
        if controller.cancel() is Some(request) {
          set_pending(None)
          controller.restore(request)
        }
      }
      let window = @core.global_this()
      window._call("addEventListener", [@core.any("pagehide"), @core.any(leave)])
      |> ignore
      let check = fn() {
        if checking.val {
          return
        }
        checking.val = true
        @core.from_async(async fn() {
          defer {
            checking.val = false
          }
          try {
            let response = ui_call(window, "fetch", [
              @core.any("/api/health"),
              host_record({ "signal": health._get("signal") }),
            ])
            if !truthy(response._get("ok")) {
              chat_error("Health check failed")
            }
            let data = ui_call(response, "json", [])
            if active.val {
              set_available(Some(@core.equal(data._get("ai"), @core.any(true))))
            }
          } catch {
            _ => if active.val { set_available(Some(false)) }
          }
        })
        |> ignore
      }
      check()
      let timer = window._call("setInterval", [
        @core.any(check),
        @core.any(15000),
      ])
      fn() {
        active.val = false
        window._call("clearInterval", [timer]) |> ignore
        health._call("abort", []) |> ignore
        window._call("removeEventListener", [
          @core.any("pagehide"),
          @core.any(leave),
        ])
        |> ignore
        controller.cancel() |> ignore
      }
    },
    [],
  )
  @react.use_effect(
    fn() {
      if truthy(store._call("snapshot", [])._get("synced")) {
        let peers : FixedArray[@core.Any] = editor._get("peers").cast()
        for value in messages {
          let message = @boundary.read_chat_message(value)
          if message.author_id != controller.author_id ||
            message.status != Some(@editor.Pending) ||
            request
            .get_current()
            .map(fn(request) { request.message_id == message.id })
            .unwrap_or(false) {
            continue
          }
          let mut connected = false
          for peer in peers {
            if message.request_client_id ==
              Some((peer._get("clientId").cast() : Double)) {
              connected = true
              break
            }
          }
          if !connected {
            controller.status(message.id, @editor.Cancelled)
          }
        }
      }
      fn() { () }
    },
    [@core.any(messages), chat, store, editor._get("peers")],
  )
  @react.use_layout_effect(
    fn() {
      if controller.active {
        let id = if messages.is_empty() {
          None
        } else {
          Some((messages[messages.length() - 1]._get("id").cast() : String))
        }
        if follow.val {
          controller.show_latest()
        } else if last_id.get_current() != id {
          set_new_messages(true)
        }
        last_id.set_current(id)
      }
      fn() { () }
    },
    [@core.any(messages), @core.any(controller.active)],
  )
  @react.use_effect(
    fn() {
      if request.get_current() is Some(active) &&
        active.scope.scene_id != scene_id {
        controller.cancel() |> ignore
        set_pending(None)
        controller.restore(active)
        set_error(
          "Scene を切り替えたため、依頼を停止しました。",
        )
      } else {
        set_error("")
      }
      set_prompt(drafts.get(scene_id).unwrap_or(""))
      set_retry(None)
      fn() { () }
    },
    [@core.any(scene_id)],
  )
  chat_view(controller, messages, pending, error, retry, new_messages)
}

///|
fn chat_suggestions(editor : @core.Any) -> Array[String] {
  let scene = editor._get("scene")
  let compositions = scene._get("compositions")
  let order : FixedArray[String] = scene._get("compositionOrder").cast()
  let ids : FixedArray[String] = editor._get("selectedIds").cast()
  let selection = @boundary.read_chat_selection(editor._get("selection"))
  let transition = selection is @editor.Transition(_)
  if order.length() == 1 && @core.object_keys(scene._get("objects")).is_empty() {
    return [
      "円を作り、次の場面へ上向きの弧で動かして", "数式 E = mc^2 がゆっくり登場する次の場面を作って",
      "短い見出しが登場する2つの場面を作って",
    ]
  }
  if order.length() == 1 && !ids.is_empty() {
    return [
      "次の場面を作り、選択した図形を右へ動かして", "次の場面で選択した図形をフェードアウトして",
      "選択した図形を黄色にして",
    ]
  }
  if ids.length() == 1 &&
    !transition &&
    @core.equal(
      scene._get("objects")._get(ids[0])._get("kind"),
      @core.any("path"),
    ) {
    return [
      "この曲線を上に大きく曲げて", "この曲線を黄色にして",
      "線を少し太くして",
    ]
  }
  if !ids.is_empty() {
    for id in @core.object_keys(scene._get("transitions")) {
      let target = scene._get("transitions")._get(id)
      let from = compositions._get(target._get("fromId").cast())
      let to = compositions._get(target._get("toId").cast())
      let mut visible = truthy(from) && truthy(to)
      if visible {
        for id in ids {
          let a = from._get("states")._get(id)
          let b = to._get("states")._get(id)
          if !truthy(a) ||
            !truthy(b) ||
            !truthy(a._get("visible")) ||
            !truthy(b._get("visible")) {
            visible = false
            break
          }
        }
      }
      if visible {
        return [
          "選択した図形を上に弧を描いて動かして", "動きの開始を 100ms 遅らせて",
          "動き始めと終わりをなめらかにして",
        ]
      }
    }
  }
  if transition {
    [
      "登場を 200ms 早めて", "動きの開始を 100ms 遅らせて", "動き始めと終わりをなめらかにして",
    ]
  } else {
    [
      "円をもう少し大きくして、黄色にして", "星のイラストを生成して右上に置いて",
      "短い見出しのテキストを追加して",
    ]
  }
}
