///|
fn decode_connection(value : @core.Any) -> @editor.Connection {
  let transport = match string_value(value._get("status")) {
    "connected" => @editor.Connected
    "disconnected" => @editor.Disconnected
    _ => @editor.Connecting
  }
  let persistence = match string_value(value._get("localPersistence")) {
    "ready" => @editor.Ready
    "loading" => @editor.Loading
    _ => @editor.Unavailable
  }
  {
    transport,
    persistence,
    synced: truthy(value._get("synced")),
    has_project: truthy(value._get("project")),
    issue: optional_string(value._get("connectionIssue")),
  }
}

///|
fn optional_string(value : @core.Any) -> String? {
  if @core.is_nullish(value) {
    None
  } else {
    Some(value.cast())
  }
}

///|
extern "js" fn make_connection_view(
  live : Bool,
  label : String,
  description : String,
  storage : String,
) -> @core.Any =
  #|(live, label, description, storage) => ({live, label, description, storage})

///|
pub fn connection_presentation(input : @core.Any) -> @core.Any {
  let value = @editor.connection_view(decode_connection(input))
  make_connection_view(
    value.live,
    value.label,
    value.description,
    value.storage,
  )
}

///|
pub fn connection_status(input : @core.Any) -> @react.Element {
  let state = decode_connection(input._get("snapshot"))
  let view = @editor.connection_view(state)
  let details : Array[&@react.ReactNode] = [
    h(
      "p",
      {
        "className": @core.any("connection-detail"),
        "role": @core.any("status"),
      },
      [view.description],
    ),
    h(
      "p",
      {
        "className": classes([
          @core.any("connection-storage"),
          @core.any(
            if state.persistence == @editor.Unavailable {
              "connection-warning"
            } else {
              ""
            },
          ),
        ]),
      },
      [view.storage],
    ),
  ]
  if !view.live {
    details.push(
      h(
        "button",
        {
          "type": @core.any("button"),
          "className": @core.any("subtle-button connection-retry"),
          "onClick": input._get("onRetry"),
        },
        [icon("RefreshCw", 13), "再接続"],
      ),
    )
  }
  if truthy(input._get("expanded")) {
    let nodes : Array[&@react.ReactNode] = [h("strong", Map([]), [view.label])]
    nodes.append(details)
    return h(
      "section",
      {
        "className": @core.any("connection-expanded"),
        "aria-label": @core.any("共同編集の接続状態"),
      },
      nodes,
    )
  }
  let trigger : Array[&@react.ReactNode] = [
    h(
      "i",
      {
        "className": @core.any(
          if view.live && !view.warning {
            "online"
          } else {
            "offline"
          },
        ),
        "aria-hidden": @core.any("true"),
      },
      [],
    ),
    h("span", Map([]), [view.label]),
  ]
  if state.persistence == @editor.Unavailable {
    trigger.push(
      icon("AlertTriangle", 12, props={ "aria-hidden": @core.any("true") }),
    )
  }
  let content : Array[&@react.ReactNode] = [
    ui("Popover", "Title", Map([]), ["共同編集の接続"]),
  ]
  content.append(details)
  let suffix = if state.persistence == @editor.Unavailable {
    "、ブラウザ内の保存を確認できません"
  } else {
    ""
  }
  let label = "共同編集の接続状態: " + view.label + suffix
  ui("Popover", "Root", Map([]), [
    ui(
      "Popover",
      "Trigger",
      {
        "className": classes([
          @core.any("connection-status connection-trigger"),
          @core.any(if view.warning { "connection-warning" } else { "" }),
        ]),
        "aria-label": @core.any(label),
      },
      trigger,
    ),
    ui("Popover", "Portal", Map([]), [
      ui(
        "Popover",
        "Positioner",
        {
          "sideOffset": @core.any(8),
          "align": @core.any("end"),
          "className": @core.any("z-50"),
        },
        [
          ui(
            "Popover",
            "Popup",
            { "className": @core.any("connection-popup") },
            content,
          ),
        ],
      ),
    ]),
  ])
}

///|
fn decode_status(value : @core.Any) -> @editor.OperationStatus? {
  if @core.is_nullish(value) {
    return None
  }
  let kind = match string_value(value._get("kind")) {
    "active" => @editor.Active
    "complete" => @editor.Complete
    "cancelled" => @editor.Cancelled
    "locked" => @editor.Locked
    _ => @editor.Inactive
  }
  Some({
    label: value._get("label").cast(),
    detail: optional_string(value._get("detail")),
    kind,
  })
}

///|
extern "js" fn status_value(
  label : String,
  detail : @core.Any,
  kind : String,
) -> @core.Any =
  #|(label, detail, kind) => detail == null ? {label, kind} : {label, detail, kind}

///|
fn encode_status(status : @editor.OperationStatus?) -> @core.Any {
  match status {
    None => @core.null()
    Some(status) =>
      status_value(
        status.label,
        @core.from_option(status.detail),
        @editor.feedback_name(status.kind),
      )
  }
}

///|
extern "js" fn schedule_timer(f : () -> Unit, delay : Int) -> @core.Any =
  #|(f, delay) => globalThis.setTimeout(f, delay)

///|
extern "js" fn cancel_timer(id : @core.Any) -> Unit =
  #|id => globalThis.clearTimeout(id)

///|
extern "js" fn feedback_value(
  status : @core.Any,
  report : (@core.Any) -> Unit,
) -> @core.Any =
  #|(feedback, report) => ({feedback, report})

///|
pub fn use_operation_feedback(scope : String) -> @core.Any {
  let initial : @editor.FeedbackState = { revision: 0, entry: None, }
  let (state, dispatch) = @react.use_reducer(@editor.reduce_feedback, initial)
  let report = @react.use_callback(
    fn(value : @core.Any) {
      dispatch(@editor.Report(scope, decode_status(value)))
    },
    [@core.any(scope)],
  )
  @react.use_effect(
    fn() {
      if state.entry is Some(entry) && @editor.is_completion(entry.status) {
        let timer = schedule_timer(
          fn() { dispatch(@editor.Expire(state.revision)) },
          2800,
        )
        fn() { cancel_timer(timer) }
      } else {
        fn() { () }
      }
    },
    [@core.any(state.entry)],
  )
  let status = match state.entry {
    Some(entry) if entry.scope == scope => Some(entry.status)
    _ => None
  }
  feedback_value(encode_status(status), report)
}

///|
pub fn operation_feedback(input : @core.Any) -> @react.Element {
  let status = decode_status(input._get("status"))
  let nodes : Array[&@react.ReactNode] = []
  if status is Some(status) {
    let name = match status.kind {
      Complete => "Check"
      Cancelled => "X"
      Locked => "LockKeyhole"
      Active => "Move"
      Inactive => "MousePointer2"
    }
    let content : Array[&@react.ReactNode] = [
      icon(name, 13, props={ "aria-hidden": @core.any("true") }),
      h("span", { "className": @core.any("operation-feedback-label") }, [
        status.label,
      ]),
    ]
    if status.detail is Some(detail) && !detail.is_empty() {
      content.push(
        h("span", { "className": @core.any("operation-feedback-detail") }, [
          detail,
        ]),
      )
    }
    nodes.push(
      h(
        "div",
        { "className": @core.any("operation-feedback-content") },
        content,
      ),
    )
  }
  nodes.push(
    h(
      "span",
      {
        "className": @core.any("operation-feedback-announcement"),
        "role": @core.any("status"),
        "aria-live": @core.any("polite"),
        "aria-atomic": @core.any("true"),
      },
      [@editor.announcement(status)],
    ),
  )
  h(
    "div",
    {
      "className": classes([
        @core.any("operation-feedback"),
        input._get("className"),
      ]),
      "data-feedback-state": @core.any(
        status.map(fn(s) { @editor.feedback_name(s.kind) }).unwrap_or("empty"),
      ),
    },
    nodes,
  )
}
