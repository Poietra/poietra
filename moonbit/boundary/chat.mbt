///|
pub fn read_chat_selection(value : @core.Any) -> @editor.ChatSelection {
  let id : String = value._get("id").cast()
  if strict_equal(value._get("kind"), @core.any("transition")) {
    @editor.Transition(id)
  } else {
    @editor.Composition(id)
  }
}

///|
pub fn write_chat_selection(value : @editor.ChatSelection) -> @core.Any {
  let (kind, id) = match value {
    Composition(id) => ("composition", id)
    Transition(id) => ("transition", id)
  }
  @core.from_entries([("kind", @core.any(kind)), ("id", @core.any(id))])
}

///|
pub fn read_chat_scope(value : @core.Any) -> @editor.ChatScope {
  let ids : FixedArray[String] = value._get("selectedIds").cast()
  {
    scene_id: value._get("sceneId").cast(),
    selection: read_chat_selection(value._get("selection")),
    selected_ids: Array::makei(ids.length(), fn(i) { ids[i] }),
    label: value._get("label").cast(),
  }
}

///|
pub fn write_chat_scope(scope : @editor.ChatScope) -> @core.Any {
  @core.from_entries([
    ("sceneId", @core.any(scope.scene_id)),
    ("selection", write_chat_selection(scope.selection)),
    (
      "selectedIds",
      @core.any(
        FixedArray::makei(scope.selected_ids.length(), fn(i) {
          scope.selected_ids[i]
        }),
      ),
    ),
    ("label", @core.any(scope.label)),
  ])
}

///|
pub fn read_chat_message(value : @core.Any) -> @editor.ChatMessage[@core.Any] {
  {
    id: value._get("id").cast(),
    role: if strict_equal(value._get("role"), @core.any("user")) {
      @editor.Person
    } else {
      @editor.Assistant
    },
    content: value._get("content").cast(),
    scope: read_chat_scope(value._get("scope")),
    author_id: value._get("authorId").cast(),
    author_name: value._get("authorName").cast(),
    color: value._get("color").cast(),
    created_at: value._get("createdAt").cast(),
    mentions_codex: @project_codec.optional(value._get("mentionsCodex"), fn(v) {
      v.cast()
    }),
    reply_to: @project_codec.optional(value._get("replyTo"), fn(v) { v.cast() }),
    request_client_id: @project_codec.optional(value._get("requestClientId"), fn(
      v,
    ) {
      v.cast()
    }),
    status: if @core.is_undefined(value._get("status")) {
      None
    } else {
      @editor.chat_status(value._get("status").cast())
    },
    proposal: @project_codec.optional(value._get("proposal"), fn(v) { v }),
    applied: @project_codec.optional(value._get("applied"), fn(v) { v.cast() }),
    dismissed: @project_codec.optional(value._get("dismissed"), fn(v) {
      v.cast()
    }),
  }
}

///|
pub fn write_chat_message(value : @editor.ChatMessage[@core.Any]) -> @core.Any {
  let result = @core.from_entries([
    ("id", @core.any(value.id)),
    (
      "role",
      @core.any(if value.role == @editor.Person { "user" } else { "assistant" }),
    ),
    ("content", @core.any(value.content)),
    ("scope", write_chat_scope(value.scope)),
    ("authorId", @core.any(value.author_id)),
    ("authorName", @core.any(value.author_name)),
    ("color", @core.any(value.color)),
    ("createdAt", @core.any(value.created_at)),
  ])
  if value.mentions_codex is Some(v) {
    result._set("mentionsCodex", @core.any(v))
  }
  if value.reply_to is Some(v) {
    result._set("replyTo", @core.any(v))
  }
  if value.request_client_id is Some(v) {
    result._set("requestClientId", @core.any(v))
  }
  if value.status is Some(v) {
    result._set("status", @core.any(@editor.chat_status_name(v)))
  }
  if value.proposal is Some(v) {
    result._set("proposal", v)
  }
  if value.applied is Some(v) {
    result._set("applied", @core.any(v))
  }
  if value.dismissed is Some(v) {
    result._set("dismissed", @core.any(v))
  }
  result
}

///|
pub fn codex_mention(text : String) -> String? {
  let found = Ref(false)
  let regexp = @core.new(@core.global_this()._get("RegExp"), [
    @core.any("(^|[^\\p{L}\\p{N}_@＠/])[@＠]codex(?![a-z0-9_-])"),
    @core.any("giu"),
  ])
  let stripped : String = @core.any(text)
    ._call("replace", [
      regexp,
      @core.any(fn(_match : String, prefix : String) {
        found.val = true
        prefix
      }),
    ])
    .cast()
  if found.val {
    Some(stripped.trim().to_owned())
  } else {
    None
  }
}

///|
pub fn codex_prompt(text : String) -> @core.Any {
  codex_mention(text).map(@core.any).unwrap_or(@core.null())
}

///|
fn read_conversation_turn(value : @core.Any) -> @editor.ConversationTurn {
  let status = if @core.is_undefined(value._get("proposalStatus")) {
    None
  } else {
    match (value._get("proposalStatus").cast() : String) {
      "applied" => Some(@editor.Applied)
      "discarded" => Some(@editor.Discarded)
      _ => Some(@editor.Proposed)
    }
  }
  {
    role: if strict_equal(value._get("role"), @core.any("user")) {
      @editor.Person
    } else {
      @editor.Assistant
    },
    content: value._get("content").cast(),
    proposal_status: status,
  }
}

///|
fn write_conversation_turn(value : @editor.ConversationTurn) -> @core.Any {
  let result = @core.from_entries([
    (
      "role",
      @core.any(if value.role == @editor.Person { "user" } else { "assistant" }),
    ),
    ("content", @core.any(value.content)),
  ])
  if value.proposal_status is Some(status) {
    result._set(
      "proposalStatus",
      @core.any(@editor.proposal_status_name(status)),
    )
  }
  result
}

///|
pub fn trim_ai_history(
  history : FixedArray[@core.Any],
) -> FixedArray[@core.Any] {
  let result = @editor.trim_history(
    Array::makei(history.length(), fn(i) { read_conversation_turn(history[i]) }),
  )
  FixedArray::makei(result.length(), fn(i) {
    write_conversation_turn(result[i])
  })
}

///|
pub fn chat_history(
  messages : FixedArray[@core.Any],
  scene_id : String,
  author_id : String,
) -> FixedArray[@core.Any] {
  let result = @editor.chat_history(
    Array::makei(messages.length(), fn(i) { read_chat_message(messages[i]) }),
    scene_id,
    author_id,
    codex_mention,
    fn(proposal) {
      let changes : FixedArray[@core.Any] = proposal._get("changes").cast()
      !changes.is_empty()
    },
  )
  FixedArray::makei(result.length(), fn(i) {
    write_conversation_turn(result[i])
  })
}
