///|
fn chat_uuid() -> String {
  @core.global_this()._get("crypto")._call("randomUUID", []).cast()
}

///|
fn chat_error(message : String) -> Unit raise {
  @core.throwable(fn() { @core.throw_error(message) })
}

///|
fn ChatController::send(
  self : ChatController,
  value : String,
  retry_id : String?,
  automatic : Bool,
) -> Unit {
  @core.from_async(async fn() { self.send_async(value, retry_id, automatic) })
  |> ignore
}

///|
async fn ChatController::send_async(
  self : ChatController,
  value : String,
  retry_id : String?,
  automatic : Bool,
) -> Unit {
  let text = value.trim().to_owned()
  if text.is_empty() {
    return
  }
  let mention = @boundary.codex_mention(text)
  let selected : FixedArray[String] = self.editor._get("selectedIds").cast()
  let error = if text.length() > 3000 {
    "メッセージは 3,000 文字以内で入力してください。"
  } else if mention is Some(_) && truthy(self.editor._get("viewingPlayback")) {
    "「この場面を編集」で編集に戻ってから Codex に依頼してください。"
  } else if mention is Some(_) && self.request.get_current() is Some(_) {
    "Codex の返答を待つか、現在の依頼を停止してください。"
  } else if mention == Some("") {
    "@codex の後に、頼みたいことを入力してください。"
  } else if mention is Some(_) && self.available != Some(true) {
    "Codex の接続を準備しています。メンバーへのメッセージは送れます。"
  } else if mention is Some(_) && selected.length() > 100 {
    "Codex への依頼では、選択するオブジェクトを100個以内にしてください。"
  } else {
    ""
  }
  if !error.is_empty() {
    (self.set_error)(error)
    return
  }
  let scene = self.editor._get("scene")
  let selection = @boundary.read_chat_selection(self.editor._get("selection"))
  let target = match selection {
    Composition(id) =>
      optional_string(scene._get("compositions")._get(id)._get("name")).unwrap_or(
        "Composition",
      )
    Transition(_) => "Transition"
  }
  let names = []
  for id in selected {
    let object = scene._get("objects")._get(id)
    if truthy(object) {
      names.push(string_value(object._get("name")))
    }
  }
  let label = string_value(scene._get("name")) +
    " · " +
    target +
    (if names.is_empty() { "" } else { " · " + names.join(", ") })
  let scope : @editor.ChatScope = {
    scene_id: self.scene_id,
    selection,
    selected_ids: Array::makei(selected.length().min(100), fn(i) { selected[i] }),
    label: label[:label.length().min(2000)].to_owned(),
  }
  let messages = chat_messages(self.chat)
  let own = messages.filter(fn(message) {
    message.scope.scene_id == scope.scene_id &&
    message.author_id == self.author_id
  })
  let previous = match retry_id {
    Some(id) => own.iter().find_first(fn(message) { message.id == id })
    None =>
      match own.last() {
        Some(last) =>
          if mention is Some(_) &&
            last.role == @editor.Person &&
            (
              last.status == Some(@editor.Cancelled) ||
              last.status == Some(@editor.Failed)
            ) &&
            last.content == text {
            Some(last)
          } else {
            None
          }
        None => None
      }
  }
  let id = previous.map(fn(message) { message.id }).unwrap_or_else(chat_uuid)
  let history = @boundary.chat_history(
    self.chat._call("snapshot", []).cast(),
    scope.scene_id,
    self.author_id,
  )
  let name : String = self.store._get("userName").cast()
  let message : @editor.ChatMessage[@core.Any] = {
    id,
    role: @editor.Person,
    content: text,
    scope,
    status: Some(
      if mention is Some(_) {
        @editor.Pending
      } else {
        @editor.Complete
      },
    ),
    mentions_codex: Some(mention is Some(_)),
    request_client_id: Some(self.store._get("doc")._get("clientID").cast()),
    author_id: self.author_id,
    author_name: name[:name.length().min(40)].to_owned(),
    color: self.store._get("color").cast(),
    created_at: @core.global_this()._get("Date")._call("now", []).cast(),
    reply_to: None,
    proposal: None,
    applied: None,
    dismissed: None,
  }
  let request : ChatRequest = {
    controller: new_controller(),
    scope,
    prompt: text,
    message_id: id,
  }
  if mention is Some(_) {
    self.request.set_current(Some(request))
    (self.set_pending)(Some(request))
  }
  (self.set_error)("")
  (self.set_retry)(None)
  if self.prompt.trim().to_owned() == text {
    self.update_prompt("")
  }
  self.follow.val = true
  defer (if self.owns(request) {
    self.request.set_current(None)
    (self.set_pending)(None)
  })
  // Navigation may abort fetch before pagehide, making it look like a network
  // failure. Cancel while this request is still owned. Attach only while an AI
  // request is running and remove on every exit, including an explicit stop.
  let window = @core.global_this()
  let leave = @core.any(fn() {
    if self.owns(request) && self.cancel() is Some(active) {
      (self.set_pending)(None)
      self.restore(active)
    }
  })
  if mention is Some(_) {
    window._call("addEventListener", [@core.any("beforeunload"), leave])
    |> ignore
  }
  defer (if mention is Some(_) {
    window._call("removeEventListener", [@core.any("beforeunload"), leave])
    |> ignore
  })
  try {
    @core.throwable(fn() {
      if previous is Some(_) {
        self.status(id, message.status.unwrap())
      } else {
        self.chat._call("append", [@boundary.write_chat_message(message)])
        |> ignore
      }
    })
    guard mention is Some(prompt) else { return }
    let body = host_record({
      "roomId": self.store._get("roomId"),
      "sceneId": @core.any(scope.scene_id),
      "compositionId": self.editor._get("compositionId"),
      "transitionId": match selection {
        Transition(id) => @core.any(id)
        _ => @core.null()
      },
      "selectedIds": @core.any(host_array(scope.selected_ids)),
      "prompt": @core.any(prompt),
      "history": @core.any(history),
      "supportsCompositionAppends": @core.any(true),
    })
    let response = ui_call(@core.global_this(), "fetch", [
      @core.any("/api/ai/propose"),
      host_record({
        "method": @core.any("POST"),
        "headers": host_record({ "Content-Type": @core.any("application/json") }),
        "signal": request.controller._get("signal"),
        "body": @core.global_this()._get("JSON")._call("stringify", [body]),
      }),
    ])
    let data = ui_call(response, "json", []) catch {
      _ => {
        chat_error(
          "応答を読み取れませんでした。もう一度お試しください。",
        )
        @core.null()
      }
    }
    if !self.owns(request) ||
      ui_aborted(request.controller._get("signal")) ||
      self.current_scene.get_current() != Some(scope.scene_id) {
      return
    }
    if !truthy(response._get("ok")) {
      chat_error(
        optional_string(data._get("error")).unwrap_or(
          "編集案を作成できませんでした。",
        ),
      )
    }
    if !@boundary.valid_chat_proposal(data) {
      chat_error(
        "編集案を読み取れませんでした。もう一度お試しください。",
      )
    }
    if !truthy(
        self.store._call("project", [])._get("scenes")._get(scope.scene_id),
      ) {
      chat_error("編集対象の Scene が削除されています。")
    }
    let assistant_id = chat_uuid()
    @core.throwable(fn() {
      self.store
      ._get("doc")
      ._call("transact", [
        @core.any(fn() {
          self.status(id, @editor.Complete)
          self.chat._call("append", [
            @boundary.write_chat_message({
              ..message,
              id: assistant_id,
              role: @editor.Assistant,
              content: data._get("message").cast(),
              proposal: Some(data),
              reply_to: Some(id),
              author_name: "Codex",
              color: "#a79bf3",
              created_at: @core.global_this()
              ._get("Date")
              ._call("now", [])
              .cast(),
              status: None,
              mentions_codex: None,
              request_client_id: None,
            }),
          ])
          |> ignore
        }),
      ])
      |> ignore
    })
    let changes : FixedArray[@core.Any] = data._get("changes").cast()
    if automatic && !changes.is_empty() {
      self.latest.get_current().unwrap().apply(assistant_id, true)
    }
  } catch {
    failure => {
      if mention is None {
        (self.set_error)(
          "メッセージを保存できませんでした。もう一度お試しください。",
        )
        self.restore(request)
      }
      if self.owns(request) && !ui_aborted(request.controller._get("signal")) {
        self.status(id, @editor.Failed)
        (self.set_error)(
          error_message(
            ui_native_error(failure),
            "接続に失敗しました。",
          ),
        )
        (self.set_retry)(Some({ prompt: text, message_id: id, }))
      }
    }
  }
}
