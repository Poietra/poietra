///|
priv struct ChatRequest {
  controller : @core.Any
  scope : @editor.ChatScope
  prompt : String
  message_id : String
}

///|
priv struct ChatRetry {
  prompt : String
  message_id : String
}

///|
priv struct ChatController {
  editor : @core.Any
  store : @core.Any
  chat : @core.Any
  scene_id : String
  author_id : String
  prompt : String
  available : Bool?
  active : Bool
  request : @react.ReactRef[ChatRequest]
  current_scene : @react.ReactRef[String]
  latest : @react.ReactRef[ChatController]
  composer : @react.ReactRef[@core.Any]
  list : @react.ReactRef[@core.Any]
  drafts : Map[String, String]
  applied : Set[String]
  follow : Ref[Bool]
  set_prompt : (String) -> Unit
  set_pending : (ChatRequest?) -> Unit
  set_error : (String) -> Unit
  set_retry : (ChatRetry?) -> Unit
  set_new_messages : (Bool) -> Unit
  open_scene : (String) -> Unit
  edit_moment : () -> Unit
}

///|
fn chat_messages(chat : @core.Any) -> Array[@editor.ChatMessage[@core.Any]] {
  let values : FixedArray[@core.Any] = chat._call("snapshot", []).cast()
  Array::makei(values.length(), fn(i) { @boundary.read_chat_message(values[i]) })
}

///|
fn ChatController::update_prompt(self : ChatController, text : String) -> Unit {
  self.drafts[self.current_scene.get_current().unwrap()] = text
  (self.set_prompt)(text)
}

///|
fn ChatController::restore(
  self : ChatController,
  request : ChatRequest,
) -> Unit {
  let id = request.scope.scene_id
  if self.drafts.get(id).unwrap_or("").is_empty() {
    self.drafts[id] = request.prompt
  }
  if self.current_scene.get_current() == Some(id) {
    (self.set_prompt)(self.drafts.get(id).unwrap_or(""))
  }
}

///|
fn ChatController::status(
  self : ChatController,
  id : String,
  status : @editor.ChatStatus,
) -> Unit {
  self.chat._call("patch", [
    @core.any(id),
    host_record({ "status": @core.any(@editor.chat_status_name(status)) }),
  ])
  |> ignore
}

///|
fn ChatController::cancel(self : ChatController) -> ChatRequest? {
  guard self.request.get_current() is Some(request) else { return None }
  self.request.set_current(None)
  request.controller._call("abort", []) |> ignore
  self.status(request.message_id, @editor.Cancelled)
  Some(request)
}

///|
fn ChatController::stop(self : ChatController) -> Unit {
  if self.cancel() is Some(request) {
    (self.set_pending)(None)
    self.restore(request)
    (self.set_retry)(None)
    (self.set_error)(
      "依頼を停止しました。編集内容はそのままです。",
    )
  }
}

///|
fn ChatController::owns(self : ChatController, request : ChatRequest) -> Bool {
  self.request
  .get_current()
  .map(fn(current) { @core.equal(@core.any(current), @core.any(request)) })
  .unwrap_or(false)
}

///|
fn ChatController::show_latest(self : ChatController) -> Unit {
  self.follow.val = true
  (self.set_new_messages)(false)
  if self.list.get_current() is Some(list) {
    list._set("scrollTop", list._get("scrollHeight"))
  }
}

///|
fn ChatController::focus(self : ChatController) -> Unit {
  if self.composer.get_current() is Some(composer) {
    composer._call("focus", []) |> ignore
  }
}

///|
fn chat_selection_exists(
  scene : @core.Any,
  selection : @editor.ChatSelection,
) -> Bool {
  match selection {
    Composition(id) => truthy(scene._get("compositions")._get(id))
    Transition(id) => truthy(scene._get("transitions")._get(id))
  }
}

///|
fn ChatController::show_target(
  self : ChatController,
  target : @editor.ProposalTarget,
) -> Unit {
  let scene = self.editor._get("scene")
  if !chat_selection_exists(scene, target.selection) {
    (self.set_error)(
      "編集案の対象が削除されています。今の状態でもう一度依頼してください。",
    )
    return
  }
  self.editor
  ._get("select")
  ._invoke([@boundary.write_chat_selection(target.selection)])
  |> ignore
  self.editor
  ._get("setSelectedIds")
  ._invoke([
    @core.any(
      host_array(
        target.object_ids.filter(fn(id) {
          truthy(scene._get("objects")._get(id))
        }),
      ),
    ),
  ])
  |> ignore
  (self.set_error)("")
}

///|
fn ChatController::apply(
  self : ChatController,
  id : String,
  automatic : Bool,
) -> Unit {
  if truthy(self.editor._get("viewingPlayback")) {
    (self.set_error)("編集に戻ってから適用してください。")
    return
  }
  guard chat_messages(self.chat)
    .iter()
    .find_first(fn(message) { message.id == id })
    is Some(message) else {
    return
  }
  guard message.proposal is Some(proposal) else { return }
  if message.author_id != self.author_id ||
    message.applied.unwrap_or(false) ||
    message.dismissed.unwrap_or(false) ||
    self.applied.contains(id) {
    return
  }
  if message.scope.scene_id != self.scene_id {
    (self.set_error)("対象の Scene に戻って適用してください。")
    return
  }
  attempt(
    fn() {
      let targets = @boundary.read_proposal_targets(
        proposal,
        self.editor._get("scene"),
      )
      let undo = self.store._get("undoManager")
      undo._call("stopCapturing", []) |> ignore
      @core.throwable(fn() {
        // applyProposal validates guards and targets before its first write.
        self.store
        ._get("doc")
        ._call("transact", [
          @core.any(fn() {
            self.store._call("applyProposal", [proposal]) |> ignore
            self.chat._call("patch", [
              @core.any(id),
              host_record({ "applied": @core.any(true) }),
            ])
            |> ignore
          }),
          @core.any("poietra-local"),
        ])
        |> ignore
      }) catch {
        error => {
          ui_quiet(undo, "stopCapturing")
          @core.throw_(ui_native_error(error))
        }
      }
      undo._call("stopCapturing", []) |> ignore
      self.applied.add(id)
      let transition = targets
        .rev_iter()
        .find_first(fn(target) {
          target.created && target.selection is @editor.Transition(_)
        })
      let created = match transition {
        Some(target) => Some(target)
        None => targets.rev_iter().find_first(fn(target) { target.created })
      }
      if created is Some(target) {
        self.editor
        ._get("select")
        ._invoke([@boundary.write_chat_selection(target.selection)])
        |> ignore
        self.editor
        ._get("setSelectedIds")
        ._invoke([@core.any(host_array(target.object_ids))])
        |> ignore
      }
      self.editor
      ._get("notify")
      ._invoke([
        @core.any(
          if automatic {
            "Codex の編集案を即適用しました。Undo で戻せます"
          } else {
            "編集案を適用しました。Undo で戻せます"
          },
        ),
      ])
      |> ignore
      (self.set_error)("")
      (self.set_retry)(None)
    },
    self.set_error,
    "適用できませんでした。",
  )
}
